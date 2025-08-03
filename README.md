# Setup script for Redash with Podman on Arch Linux

I forked it from the [reference setup](https://github.com/getredash/setup), that uses Docker and a bunch of other Linux distros.

## How to use this

As opposed to the original, it is not necessary to run it as root.

```
# ./setup.sh
```

Also as opposed to the original, the script does not install anything, but expects `podman` and
`podman-compose` to be installed.

> [!IMPORTANT]
> The very first time you load your Redash web interface it can take a while to appear, as the background Python code
> is being compiled.  On subsequent visits, the pages should load much quicker (near instantly).

## Optional parameters

The setup script has the following optional parameters: `--dont-start`, `--preview`, `--version`, `--base <dir>`, `--port <port>`.

These can be used independently of each other, or in combinations (with the exception that `--preview` and `--version` cannot be used together).

### --base <dir>

Use this directory as a base directory for the setup. It will be created if does not exist.

### --port <port>

Serve Redash on this port. It is directly served, no nginx. Default: 5000.

### --preview

When the `--preview` parameter is given, the setup script will install the latest `preview`
[image from Docker Hub](https://hub.docker.com/r/redash/redash/tags) instead of using the latest preview release.

```
# ./setup.sh --preview
```

### --version

When the `--version` parameter is given, the setup script will install the specified version of Redash instead of the latest stable release.

```
# ./setup.sh --version 25.1.0
```

This option allows you to install a specific version of Redash, which can be useful for testing, compatibility checks, or ensuring reproducible environments.

> [!NOTE]
> The `--version` and `--preview` options cannot be used together.

### Default Behavior

When neither `--preview` nor `--version` is specified, the script will automatically detect and install the latest stable release of Redash using the GitHub API.

### --dont-start

When this option is given, the setup script will install Redash without starting it afterwards.

This is useful for people wanting to customise or modify their Redash installation before it starts for the first time.

```
# ./setup.sh --dont-start
```

## FAQ

Please refer to the [original](https://github.com/getredash/setup?tab=readme-ov-file#faq).
