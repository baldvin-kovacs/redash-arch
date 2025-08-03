#!/usr/bin/env bash

# This script sets up dockerized Redash on Debian 12.x, Fedora 38 or later, Ubuntu LTS 20.04 & 22.04, and RHEL (and compatible) 8.x & 9.x
set -eu

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

REDASH_BASE_PATH=/opt/redash
DONT_START=no
PREVIEW=no
REDASH_VERSION=""
PORT=5000

if ! command -v podman &> /dev/null || ! command -v podman-compose &> /dev/null; then
  echo "Please install podman and podman-compose."
  exit 1
fi

if ! command -v pwgen &> /dev/null ; then
  echo "Please install pwgen."
  exit 1
fi


# Parse any user provided parameters
opts="$(getopt -o dphb: -l dont-start,preview,help,version:,base:,port: --name "$0" -- "$@")"
eval set -- "$opts"

while true
do
  case "$1" in
    -d|--dont-start)
      DONT_START=yes
      shift
      ;;
    -p|--preview)
      PREVIEW=yes
      shift
      ;;
    -b|--base)
      REDASH_BASE_PATH="$2"
      shift 2
      ;;
    --port)
      PORT="$2"
      shift 2
      ;;
    --version)
      REDASH_VERSION="$2"
      shift 2
      ;;
    -h|--help)
      echo "Redash setup script usage: $0 [-d|--dont-start] [-p|--preview] [-b|--base] [--version <tag>]"
      echo "  The --preview (also -p) option uses the Redash 'preview' Docker image instead of the last stable release"
      echo "  The --version option installs the specified version tag of Redash (e.g., 10.1.0)"
      echo "  The --dont-start (also -d) option installs Redash, but doesn't automatically start it afterwards"
      echo "  The --base (also -b) option sets the base path for the installation (/opt/redash by default)"
      exit 1
      ;;
    --)
      shift
      break
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

REDASH_ABS_BASE_PATH="$(readlink -f "$REDASH_BASE_PATH" | sed 's,/*$,,')"

create_directories() {
  echo "** Creating $REDASH_BASE_PATH directory structure for Redash **"

  if [ ! -e "$REDASH_BASE_PATH" ]; then
    mkdir -p "$REDASH_BASE_PATH"
    chown "$USER:" "$REDASH_BASE_PATH"
  fi

  mkdir -p "$REDASH_BASE_PATH"/postgres-data
}

create_env() {
  echo "** Creating Redash environment file **"

  # Minimum mandatory values (when not just developing)
  COOKIE_SECRET=$(pwgen -1s 32)
  SECRET_KEY=$(pwgen -1s 32)
  PG_PASSWORD=$(pwgen -1s 32)
  DATABASE_URL="postgresql://postgres:${PG_PASSWORD}@postgres/postgres"

  if [ -e "$REDASH_BASE_PATH"/env ]; then
    # There's already an environment file

    echo
    echo "Environment file already exists, reusing that one + and adding any missing (mandatory) values"

    # Add any missing mandatory values
    REDASH_COOKIE_SECRET=
    REDASH_COOKIE_SECRET=$(. "$REDASH_BASE_PATH"/env && echo "$REDASH_COOKIE_SECRET")
    if [ -z "$REDASH_COOKIE_SECRET" ]; then
      echo "REDASH_COOKIE_SECRET=$COOKIE_SECRET" >> "$REDASH_BASE_PATH"/env
      echo "REDASH_COOKIE_SECRET added to env file"
    fi

    REDASH_SECRET_KEY=
    REDASH_SECRET_KEY=$(. "$REDASH_BASE_PATH"/env && echo "$REDASH_SECRET_KEY")
    if [ -z "$REDASH_SECRET_KEY" ]; then
      echo "REDASH_SECRET_KEY=$SECRET_KEY" >> "$REDASH_BASE_PATH"/env
      echo "REDASH_SECRET_KEY added to env file"
    fi

    POSTGRES_PASSWORD=
    POSTGRES_PASSWORD=$(. "$REDASH_BASE_PATH"/env && echo "$POSTGRES_PASSWORD")
    if [ -z "$POSTGRES_PASSWORD" ]; then
      POSTGRES_PASSWORD=$PG_PASSWORD
      echo "POSTGRES_PASSWORD=$POSTGRES_PASSWORD" >> "$REDASH_BASE_PATH"/env
      echo "POSTGRES_PASSWORD added to env file"
    fi

    REDASH_DATABASE_URL=
    REDASH_DATABASE_URL=$(. "$REDASH_BASE_PATH"/env && echo "$REDASH_DATABASE_URL")
    if [ -z "$REDASH_DATABASE_URL" ]; then
      echo "REDASH_DATABASE_URL=postgresql://postgres:${POSTGRES_PASSWORD}@postgres/postgres" >> "$REDASH_BASE_PATH"/env
      echo "REDASH_DATABASE_URL added to env file"
    fi

    echo
    return
  fi

  echo "Generating brand new environment file"

  cat <<EOF >"$REDASH_BASE_PATH"/env
PYTHONUNBUFFERED=0
REDASH_LOG_LEVEL=INFO
REDASH_REDIS_URL=redis://redis:6379/0
REDASH_COOKIE_SECRET=$COOKIE_SECRET
REDASH_SECRET_KEY=$SECRET_KEY
POSTGRES_PASSWORD=$PG_PASSWORD
REDASH_DATABASE_URL=$DATABASE_URL
REDASH_ENFORCE_CSRF=true
REDASH_GUNICORN_TIMEOUT=60
EOF
}

setup_compose() {
  # Check for conflicts between --version and --preview options
  if [ "x$PREVIEW" = "xyes" ] && [ -n "$REDASH_VERSION" ]; then
    echo "Error: Cannot specify both --preview and --version options"
    exit 1
  fi

  # Set TAG based on provided options
  if [ "x$PREVIEW" = "xyes" ]; then
    TAG="preview"
    echo "** Using preview version of Redash **"
  elif [ -n "$REDASH_VERSION" ]; then
    TAG="$REDASH_VERSION"
    echo "** Using specified Redash version: $TAG **"
  else
    # Get the latest stable version from GitHub API
    echo "** Fetching latest stable Redash version **"
    LATEST_TAG=$(curl -s https://api.github.com/repos/getredash/redash/releases/latest | grep -Po '"tag_name": "\K.*?(?=")')
    if [ -n "$LATEST_TAG" ]; then
      # Remove 'v' prefix if present (GitHub tags use 'v', Docker tags don't)
      TAG=$(echo "$LATEST_TAG" | sed 's/^v//')
      echo "** Using latest stable Redash version: $TAG **"
    else
      # Fallback to hardcoded version if API call fails
      TAG="latest"
      echo "** Warning: Failed to fetch latest version, using fallback version: $TAG **"
    fi
  fi

  sed "s|/opt/redash|$REDASH_ABS_BASE_PATH|g;s|__TAG__|$TAG|g;s|__PORT__|$PORT|g" "$SCRIPT_DIR/data/compose.yaml" > "$REDASH_BASE_PATH/compose.yaml"
}

startup() {
  if [ "x$DONT_START" != "xyes" ]; then
    cd "$REDASH_BASE_PATH"

    echo
    echo "*********************"
    echo "** Starting Redash **"
    echo "*********************"
    echo "** Initialising Redash database **"
    podman-compose run --rm server create_db

    echo "** Starting the rest of Redash **"
    podman-compose up -d

    echo
    echo "Redash has been installed and is ready for configuring at http://$(hostname -f):$PORT"
    echo
  else
    echo
    echo "*************************************************************"
    echo "** As requested, Redash has been installed but NOT started **"
    echo "*************************************************************"
    echo
  fi
}

echo
echo "Redash installation script. :)"
echo

TIMESTAMP_NOW=$(date +'%Y.%m.%d-%H.%M')

# Do the things that aren't distro specific
create_directories
create_env
setup_compose
startup

