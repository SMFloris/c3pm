---
title: "Installation"
description: "Install c3pm for the C3 programming language and choose a Nix backend."
permalink: /docs/getting-started/installation/
---

The current published release supports Linux x86_64. Native CI and the release pipeline also target Linux ARM64 and macOS ARM64; only count those platforms as supported after their native end-to-end jobs pass and their release binaries are available. macOS Intel is supported through [source builds](https://github.com/SMFloris/c3pm#macos-intel-source-build-only) but is not included in CI or automated releases. On Windows, use WSL2. The Linux release binaries run without an existing C3 compiler or compatible system libc; building projects uses a separate Nix backend.

## Install the latest release

```sh
curl --fail --location https://c3pm.dev/install.sh | sh -
```

The installer selects the native asset by OS and architecture, verifies its checksum, and puts `c3pm` in `~/.local/bin` by default. If that directory is not on your `PATH`, open a new terminal after installation or add it to your shell configuration. A platform's asset must be present in the selected release.

Check the installation:

```sh
c3pm --version
c3pm toolchain nix status
```

## Choose a Nix backend

The installer reuses an existing Nix installation or sets one up. On Linux, you can also ask c3pm to manage `nix-portable`:

```sh
c3pm toolchain nix use portable
```

On macOS, use system Nix (`c3pm toolchain nix use system`). Managed portable Nix and `c3pm bundle` are Linux-only.

See [Installer options]({{ '/docs/reference/installer/' | relative_url }}) for custom locations, unattended installation, and choosing a Nix mode during installation.

## Create your first project

Follow the [quick start]({{ '/docs/getting-started/quickstart/' | relative_url }}) to create a windowed hello world. Its `c3c init` step requires a C3 compiler on your `PATH`. You can also start from the [SQLite example]({{ '/docs/examples/sqlite/' | relative_url }}), which already includes a project file.
