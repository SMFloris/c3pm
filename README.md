# c3pm - C3 Package Manager

`c3pm` is a C3 package manager backed by Nix. Standard C3 metadata describes
the logical dependency graph. The `vendor.c3pm` extension in `project.json`
and library `manifest.json` files supplies source, toolchain, and native-package
metadata. From those inputs, c3pm generates a reproducible Nix environment.

c3pm is written in C3 and currently targets C3 0.8.3.
Linux x86_64 releases are standalone static executables containing only c3pm.
The host does not need C3 or a compatible system libc. Nix remains a separate
backend: c3pm can use a native installation or download nix-portable on demand.

## Quickstart

Download the installer and preview its choices before running it:

```sh
curl --fail --location \
  https://github.com/SMFloris/c3pm/releases/latest/download/install.sh \
  --output install.sh
sh install.sh --dry-run
sh install.sh
```

The installer supports Linux x86_64. It installs any missing bootstrap tools,
installs and verifies the latest c3pm release, and selects a Nix backend. It
uses an existing Nix installation when one is available. Otherwise it chooses
the multi-user daemon on compatible systemd hosts and the single-user install
elsewhere. Root environments without a compatible daemon use nix-portable.

Useful installer options:

```sh
# Install a particular release to a custom directory.
sh install.sh --version v0.1.0 --prefix "$HOME/bin"

# Let c3pm manage nix-portable instead of installing system Nix.
sh install.sh --nix portable

# Install only c3pm and configure Nix later.
sh install.sh --nix none

# Preview every choice without changing the machine.
sh install.sh --dry-run
```

Use `--yes` for unattended installation and `--no-modify-path` to leave
`~/.profile` untouched. Run `sh install.sh --help` for all options and their
environment-variable equivalents. The installer supports `apt`, `dnf`/`yum`,
`pacman`, `zypper`, and `apk` when bootstrap packages are missing.

The installer verifies the release checksum before replacing an existing c3pm
binary. Its default destination is `$HOME/.local/bin/c3pm`.

Try the SQLite todo example:

```sh
git clone https://github.com/SMFloris/c3pm.git
cd c3pm/examples/sqlite-example

# Resolve the C3 graph, SQLite, nixpkgs, and the development environment.
c3pm install

# Build and run inside the locked development environment.
c3pm shell -- c3c build
c3pm shell -- ./build/sqlite_example add "ship c3pm"
c3pm shell -- ./build/sqlite_example list

# Produce dist/sqlite_example as one portable executable.
c3pm bundle
./dist/sqlite_example list
```

When selected, the portable backend is stored separately from c3pm. Its first
Nix operation initializes nix-portable and may fetch the inputs recorded in
`.c3pm/nix/flake.lock`; later commands reuse that store and lock.

## Usage

Run `c3pm` from a directory containing `project.json`, or from one of its
subdirectories. c3pm discovers the project root automatically.

```text
c3pm dep <add|remove|list> ...
c3pm link <add|remove|list> ...
c3pm toolchain <show|c3c|nixpkgs|nix> ...
c3pm install
c3pm shell [-- COMMAND...]
c3pm bundle [TARGET] [--output PATH]
```

### Select a Nix backend

Inspect the active backend:

```sh
c3pm toolchain nix status
```

The status report includes the selected backend, executable path, Nix version,
and whether the selection came from configuration, `PATH`, or an environment
override.

With no saved selection, c3pm automatically uses `nix` from `PATH`. Select and
persist that executable explicitly with:

```sh
c3pm toolchain nix use system
```

If Nix is not installed, let c3pm download and select nix-portable:

```sh
c3pm toolchain nix use portable
```

This downloads the host-architecture nix-portable `v012` executable to
`$XDG_DATA_HOME/c3pm/nix-portable`. When `XDG_DATA_HOME` is unset, c3pm uses
`$HOME/.local/share/c3pm/nix-portable`.

To select another native Nix executable, provide its command name or path:

```sh
c3pm toolchain nix use nix
c3pm toolchain nix use /opt/nix/bin/nix
```

The selected backend is recorded in `$XDG_CONFIG_HOME/c3pm/config.json`, or
`$HOME/.config/c3pm/config.json` when `XDG_CONFIG_HOME` is unset. Backend
commands work outside a C3 project. A saved selection takes precedence over
automatic `nix` discovery. Return to automatic discovery with:

```sh
c3pm toolchain nix reset
```

If `c3pm toolchain nix status` cannot find any backend, it suggests installing
Nix or running `c3pm toolchain nix use portable`.

For one-off overrides, `C3PM_NIX=/path/to/nix` selects a native Nix client and
`C3PM_NIX_PORTABLE=/path/to/nix-portable` selects a nix-portable launcher.
These environment variables take precedence over the saved configuration.

### Configure the project toolchain

```sh
c3pm toolchain c3c set 0.8.3
c3pm toolchain nixpkgs set github:NixOS/nixpkgs/nixpkgs-unstable
c3pm toolchain show
```

The C3 and nixpkgs settings are project metadata. The `toolchain nix` setting
selects the local executable used to realize that environment and is stored in
the user configuration, not in the project. A C3 version override requires the
selected nixpkgs revision to provide that exact compiler version.

Use `c3pm toolchain c3c reset` or `c3pm toolchain nixpkgs reset` to remove a
project override. `c3pm toolchain nixpkgs update` updates only the locked
nixpkgs input while preserving the configured reference.

### Add a C3 dependency

```sh
c3pm dep add github:OWNER/REPO --rev REF [--subdir PATH]
```

For example:

```sh
c3pm dep add github:SMFloris/c3c-vendor \
  --rev c3pm \
  --subdir libraries/sqlite3.c3l
```

`dep add` fetches the source through Nix, reads the selected `.c3l` manifest,
and uses its `provides` value as the dependency name. `--name NAME` can assert
the expected `provides` name. The supported source forms are:

| Source | Required options | Purpose |
| --- | --- | --- |
| `github:OWNER/REPO` | `--rev REF` | GitHub repository |
| `git+https://HOST/PATH` | `--rev REF` | Git repository over HTTPS |
| `git+ssh://HOST/PATH` | `--rev REF` | Git repository over SSH |
| `archive+https://HOST/PATH` | `--sha256 sha256-...` | Fixed-output archive |
| `path:PATH` | none | Local directory |

Use `--subdir PATH` to select the `.c3l` directory inside a fetched dependency.
All remote references are recorded in `.c3pm/nix/flake.lock`.

### Remove a dependency

```sh
c3pm dep remove NAME
```

For example:

```sh
c3pm dep remove sqlite3
```

`dep remove` removes a direct project dependency, recalculates reachability, and
prunes generated C3 nodes and source inputs that are no longer needed. Shared
transitive dependencies remain available when another dependency still uses
them.

Use `--for-target TARGET` on add or remove for target-specific dependencies.
Inspect declarations with:

```sh
c3pm dep list
c3pm dep list --for-target server
```

### Link a native library or C3 project

Link a native library supplied by nixpkgs:

```sh
c3pm link add sqlite3 --nix-package sqlite --runtime
```

A Nix file is imported with an explicit `pkgs` argument instead of being
looked up as a nixpkgs attribute:

```sh
c3pm link add custom --nix-package path:./nix/custom.nix
```

Link a static or dynamic target from another C3 project:

```sh
c3pm link add protocol \
  --source git+ssh://git@example.com/acme/protocol.git \
  --rev v1.0.0 \
  --c3c-target protocol-static \
  --passthrough \
  --for-target server
```

`--c3c-target none` and `--runtime` are the defaults. A selected C3 target must
be a `static-lib` or `dynamic-lib` target in the linked project. Runtime links
are private Nix inputs; passthrough links become propagated Nix inputs. When a
link has a fetched source, `--nix-package path:./package.nix` resolves within
that source and evaluates it as `import path { inherit pkgs; }`.

Use `--subdir PATH` to select the linked project directory within its source.
Remove or inspect links with:

```sh
c3pm link remove sqlite3
c3pm link list
c3pm link list --for-target server
```

Pass the same `--for-target TARGET` to `link remove` that was used when adding
a target-specific link.

### Install or synchronize

```sh
c3pm install
```

`install` synchronizes `.c3pm/nix/` and `lib/*.c3l` with `project.json` and all
reachable library manifests. It discovers transitive dependencies, validates
Nix package attributes, preserves already locked refs, builds the C3 library
tree, and updates generated state atomically.

Run it after manually editing project or library metadata. Repeating it with
unchanged inputs is safe and reuses `.c3pm/nix/flake.lock`.

### Enter the development shell

Start an interactive shell:

```sh
c3pm shell
```

Run one command without entering an interactive session:

```sh
c3pm shell -- c3c build
c3pm shell -- c3c test
c3pm shell -- ./build/my_app
```

`shell` runs `install` first, then enters the locked Nix environment containing
`c3c`, all declared native packages, compiler and linker configuration, and the
complete generated `lib/*.c3l` tree.

### Build a portable executable

When the project has exactly one executable target:

```sh
c3pm bundle
```

Select a target when the project has multiple executables:

```sh
c3pm bundle server
```

Override the output path:

```sh
c3pm bundle server --output ./release/backend
```

The default output is `dist/<target>`. `bundle` supports executable targets
only and produces a regular Linux executable rather than a Nix-store symlink.
Nix computes the package's referenced runtime closure, and the pinned
nix-portable `zstd-fast` bundler embeds it into the resulting file.

## Current metadata format

Projects and `.c3l` manifests both use `vendor.c3pm.c3.dependencies` for source
declarations and `vendor.c3pm.nix` for native inputs. Projects can additionally
declare `toolchain` and `links`; a manifest must include the standard C3
`provides` field. This is the canonical dependency source form:

```json
{
  "dependencies": ["sqlite3"],
  "dependency-search-paths": ["lib"],
  "vendor": {
    "c3pm": {
      "toolchain": {
        "c3c": "0.8.3",
        "nixpkgs": "github:NixOS/nixpkgs/nixpkgs-unstable"
      },
      "c3": {
        "dependencies": {
          "sqlite3": {
            "source": "github",
            "owner": "SMFloris",
            "repository": "c3c-vendor",
            "rev": "c3pm",
            "subdir": "libraries/sqlite3.c3l"
          }
        }
      }
    }
  }
}
```

Source declarations are flat objects. c3pm accepts these location fields:

| `source` value | Location fields | Other required fields |
| --- | --- | --- |
| `github` | `owner`, `repository` | `rev` |
| `git+https` | `url` beginning with `https://` | `rev` |
| `git+ssh` | `url` beginning with `ssh://` | `rev` |
| `archive+https` | `url` beginning with `https://` | `sha256` in SRI form |
| `path` | `path` | none |

`subdir` is optional for every source type. Only these flat source objects are
supported.

Links live alongside `c3`, `nix`, and `toolchain`:

```json
{
  "targets": {
    "server": {
      "type": "executable",
      "linked-libraries": ["protocol"]
    }
  },
  "vendor": {
    "c3pm": {
      "links": {
        "protocol": {
          "source": "git+ssh",
          "url": "ssh://git@example.com/acme/protocol.git",
          "rev": "v1.0.0",
          "subdir": "project",
          "c3cTarget": "protocol-static",
          "nixPackage": "path:./package.nix",
          "mode": "passthrough",
          "forTarget": "server"
        }
      }
    }
  }
}
```

Prefer the `dep`, `link`, and `toolchain` commands over manual edits; their
changes are transactional and preserve JSONC comments.

## Locking

The sole dependency lock database is `.c3pm/nix/flake.lock`. It pins nixpkgs,
nix-portable, and every fetched C3 source. c3pm delegates fetching and locking
to Nix rather than cloning repositories or maintaining a second lock format.

For real-world library-native Nix metadata, see the manifests in
[SMFloris/c3c-vendor](https://github.com/SMFloris/c3c-vendor/tree/c3pm/libraries).

## Native dependencies and Nix

C3 and Nix metadata answer different questions. Standard C3 metadata tells the
compiler which C3 libraries and linker names are required:

```json
{
  "dependencies": ["sqlite3"],
  "linked-libraries": ["sqlite3"]
}
```

`vendor.c3pm.nix` tells Nix which packages must be present to build that code:

```json
{
  "vendor": {
    "c3pm": {
      "nix": {
        "nativeBuildInputs": ["pkg-config", "cmake"],
        "buildInputs": ["sqlite", "openssl"],
        "propagatedNativeBuildInputs": [],
        "propagatedBuildInputs": []
      }
    }
  }
}
```

The four package classes have the following roles:

- `nativeBuildInputs` contains tools executed while building, such as
  `pkg-config`, CMake, code generators, or other command-line utilities.
- `buildInputs` contains libraries and headers compiled or linked into the
  target, such as SQLite, OpenSSL, zlib, or SDL.
- `propagatedNativeBuildInputs` contains build tools that consumers of a
  packaged library must also receive.
- `propagatedBuildInputs` contains libraries that consumers must inherit when
  they use a packaged library.

Entries are nixpkgs attribute paths, not arbitrary Nix expressions. Both simple
names and nested attributes are supported:

```json
{
  "buildInputs": [
    "openssl",
    "xorg.libX11",
    "llvmPackages.clang"
  ]
}
```

c3pm validates these attributes against the locked nixpkgs revision and emits
references such as `pkgs.openssl` and `pkgs.xorg.libX11`. It gathers all four
classes from the root project and every reachable C3 dependency, deduplicates
them, and supplies the result to both the development shell and project
builder.

There is deliberately no automatic mapping from a C3 linker name to a nixpkgs
package. For example, `"linked-libraries": ["sqlite3"]` tells C3 what to pass
to the linker, while `"buildInputs": ["sqlite"]` tells Nix where the actual
headers and library come from. Library authors should declare both pieces when
they are needed.

### Native packages outside nixpkgs

Projects and library manifests can declare trusted package definitions through
`vendor.c3pm.nix.imports`:

```json
{
  "vendor": {
    "c3pm": {
      "nix": {
        "imports": ["./microui.nix"]
      }
    }
  }
}
```

Each import is a relative `.nix` path resolved from the declaring project or
`.c3l` directory and evaluated with `pkgs.callPackage`. The resulting package
is added to `buildInputs`. Absolute paths and paths containing `..` are
rejected. Unlike generated dependency nodes, declared imports are trusted,
executable Nix code.

### From native dependencies to a portable bundle

For an executable target, c3pm asks Nix to build a normal package whose primary
program is `$out/bin/<target>`. Nix records every Nix-store path referenced by
that finished package and determines its runtime closure. This includes needed
shared libraries even when they arrived through transitive package references.

```text
C3 executable package
        ↓
Nix reference graph
        ↓
complete runtime closure
        ↓
nix-portable zstd-fast bundler
        ↓
single portable Linux executable
```

c3pm does not equate `buildInputs` with runtime dependencies, run `ldd`, copy
`.so` files manually, or patch ELF paths. The pinned nix-portable bundler embeds
the package and closure and provides the virtual `/nix/store` environment when
the resulting file starts.

The bundle is therefore self-contained and can run without system copies of
SQLite, OpenSSL, Nix, or c3pm. It is not necessarily a statically linked ELF
binary: dynamically linked libraries can remain part of the embedded Nix
closure. “Portable” here means that the one output file carries and realizes
everything the packaged program references.

## Building c3pm from source

With C3 0.8.3 available:

```sh
c3c build
c3c test
./build/c3pm --help
```

With no saved backend, a source build automatically uses `nix` from `PATH`.
Select a persistent native or portable backend with `c3pm toolchain nix use`, or
use a one-command override in CI:

```sh
C3PM_NIX=nix ./build/c3pm install
C3PM_NIX=nix ./build/c3pm bundle
```

Set `C3PM_NIX_PORTABLE=/path/to/nix-portable` instead to select a particular
nix-portable bootstrap executable. The released c3pm executable never embeds
Nix or nix-portable.

## License

MIT. See [LICENSE](LICENSE).
