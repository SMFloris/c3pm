---
title: "Installer options"
description: "Installation locations, Nix modes, command options, and environment variables."
permalink: /docs/reference/installer/
---

Download the installer before using the options below:

```sh
curl --fail --location https://c3pm.dev/install.sh --output install.sh
```

## Install location

c3pm installs to this directory by default:

```text
$HOME/.local/bin/c3pm
```

## Installer behavior

The installer does the following:

- selects Linux x86_64, Linux ARM64, macOS ARM64, or macOS Intel assets when the release provides them;
- installs missing bootstrap tools when needed;
- downloads and verifies the latest c3pm release;
- reuses an existing Nix installation when available;
- otherwise chooses a suitable Nix setup automatically.

On a compatible Linux systemd host, the installer prefers the multi-user Nix daemon. Other non-root Linux hosts use a single-user installation; a root environment without a compatible daemon uses `nix-portable`. On macOS, the installer uses an existing Nix installation or the daemon installer; `--nix portable` and `--nix single-user` are rejected. The installer updates `~/.profile` on Linux or `~/.zprofile` on macOS unless disabled.

## Options

| Option | Purpose | Environment equivalent |
| --- | --- | --- |
| `--version VERSION` | Release tag to install; defaults to `latest` | `C3PM_VERSION` |
| `--prefix DIRECTORY` | Installation directory; defaults to `~/.local/bin` | `C3PM_INSTALL_DIR` |
| `--nix MODE` | `auto`, `daemon`, `single-user`, `portable`, or `none` | `C3PM_NIX_MODE` |
| `--yes` | Run without confirmation prompts | `C3PM_YES` |
| `--no-modify-path` | Leave `~/.profile` unchanged | `C3PM_NO_MODIFY_PATH` |
| `--dry-run` | Print the installation plan | — |
| `--help`, `-h` | Show usage | — |

```sh
# Install the current documented release to a custom directory.
sh install.sh --version v{{ site.c3pm_version }} --prefix "$HOME/bin"

# On Linux, let c3pm manage nix-portable instead of installing system Nix.
sh install.sh --nix portable

# Install c3pm only and configure Nix later.
sh install.sh --nix none

# Preview all actions without changing the system.
sh install.sh --dry-run
```

For unattended installs, add `--yes`. To keep `~/.profile` unchanged, add `--no-modify-path`.

```sh
sh install.sh --help
```

The installer can bootstrap packages through `apt`, `dnf`/`yum`, `pacman`, `zypper`, or `apk`.
On Arch Linux, prerequisite installation performs a full `pacman -Syu` sync and upgrade to avoid a partial upgrade.

Release checksums are verified before an existing c3pm binary is replaced.
