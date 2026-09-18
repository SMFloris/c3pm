# c3pm — C3 Package Manager

`c3pm` is a package manager for C3 projects, backed by Nix.

It uses standard C3 metadata for the logical dependency graph and adds `vendor.c3pm` metadata for source locations, toolchains, and native packages. From that information, c3pm creates a reproducible Nix-based development and build environment.

> [!WARNING]
> **Current supported platform: Linux x86_64.**

> [!NOTE]
> **Default nixpkgs target:** nixpkgs-unstable.
> **Default C3 target:** C3 0.8.3.

Released c3pm binaries are standalone static executables. You do **not** need C3 or a compatible system libc installed to run c3pm itself. Nix remains a separate backend: c3pm can use an existing Nix installation or manage `nix-portable` for you.

## Quick start

### 1. Install c3pm

Download the installer, then run it:

```sh
curl --fail --location \
  https://github.com/SMFloris/c3pm/releases/latest/download/install.sh | sh -
```

By default, c3pm is installed to:

```text
$HOME/.local/bin/c3pm
```

The installer:

- supports Linux x86_64;
- installs missing bootstrap tools when needed;
- downloads and verifies the latest c3pm release;
- reuses an existing Nix installation when available;
- otherwise chooses a suitable Nix setup automatically.

On compatible systemd hosts it prefers the multi-user Nix daemon. Elsewhere it uses a single-user installation. Root environments without a compatible daemon use `nix-portable`.

Useful installer options:

```sh
# Install a specific release to a custom directory.
sh install.sh --prefix "$HOME/bin"

# Let c3pm manage nix-portable instead of installing system Nix.
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

The installer also supports environment-variable equivalents for its options and can bootstrap packages through `apt`, `dnf`/`yum`, `pacman`, `zypper`, or `apk`.

Release checksums are verified before an existing c3pm binary is replaced.

### 2. Try the example project

Clone the repository and run the SQLite todo example:

```sh
git clone https://github.com/SMFloris/c3pm.git
cd c3pm/examples/sqlite-example

# Resolve C3 dependencies, SQLite, nixpkgs, and the dev environment.
c3pm install

# Build and run inside the locked environment.
c3pm shell -- c3c build
c3pm shell -- ./build/sqlite_example add "ship c3pm"
c3pm shell -- ./build/sqlite_example list

# Produce one portable executable.
c3pm bundle
./dist/sqlite_example list
```

If c3pm is using the portable Nix backend, the first Nix operation initializes `nix-portable` and may fetch inputs from `.c3pm/nix/flake.lock`. Later commands reuse the same store and lock.

## Command overview

Run c3pm from a directory containing `project.json` or from any subdirectory. c3pm finds the project root automatically.

```text
c3pm dep <add|remove|list> ...
c3pm link <add|remove|list> ...
c3pm toolchain <show|c3c|nixpkgs|nix> ...
c3pm install
c3pm shell [-- COMMAND...]
c3pm bundle [TARGET] [--output PATH]
```

Most projects follow this workflow:

```text
configure toolchain → add dependencies/links → install → build/test in shell → bundle
```

## Toolchain

c3pm manages the project C3 compiler and nixpkgs revision, while the Nix backend itself is selected per user.

### C3

The default C3 target is **0.8.3**. You can pin or reset the compiler version for a project:

```sh
c3pm toolchain c3c set 0.8.3
c3pm toolchain c3c reset
```

Use the selected compiler inside the project environment:

```sh
c3pm shell -- c3c --version
```

c3pm locks `github:c3lang/c3c/v<VERSION>` as a source input and overrides the
nixpkgs C3 package with that version and source. Nix records the resolved source
hash in `.c3pm/nix/flake.lock`.

### nixpkgs

Pin the nixpkgs revision used by the project:

```sh
c3pm toolchain nixpkgs set github:NixOS/nixpkgs/nixpkgs-unstable
c3pm toolchain nixpkgs update
c3pm toolchain nixpkgs reset
```

`update` refreshes the locked nixpkgs input while keeping the configured reference. C3 and nixpkgs settings are stored in project metadata.

Inspect the project toolchain with:

```sh
c3pm toolchain show
```

### Nix

c3pm uses Nix to realize the project environment. With no saved selection, it uses `nix` from `PATH` automatically.

```sh
c3pm toolchain nix status
c3pm toolchain nix use system
c3pm toolchain nix use portable
c3pm toolchain nix use /opt/nix/bin/nix
c3pm toolchain nix reset
```

`portable` lets c3pm download and manage `nix-portable`. The selected Nix backend is user configuration, not project metadata, and backend commands work outside a C3 project.

For one-off overrides:

```sh
C3PM_NIX=/path/to/nix c3pm install
C3PM_NIX_PORTABLE=/path/to/nix-portable c3pm install
```

## C3 dependencies

### Add a dependency

```sh
c3pm dep add github:OWNER/REPO --rev REF [--subdir PATH]
```

Example:

```sh
c3pm dep add github:SMFloris/c3c-vendor \
  --rev c3pm \
  --subdir libraries/sqlite3.c3l
```

`dep add`:

1. fetches the source through Nix;
2. reads the selected `.c3l` manifest;
3. uses the manifest's `provides` value as the dependency name;
4. records remote references in `.c3pm/nix/flake.lock`.

Use `--name NAME` when you want to assert the expected `provides` value.

Supported source forms:

| Source | Required options | Use case |
| --- | --- | --- |
| `github:OWNER/REPO` | `--rev REF` | GitHub repository |
| `git+https://HOST/PATH` | `--rev REF` | Git over HTTPS |
| `git+ssh://HOST/PATH` | `--rev REF` | Git over SSH |
| `archive+https://HOST/PATH` | `--sha256 sha256-...` | Fixed-output archive |
| `path:PATH` | none | Local directory |

Use `--subdir PATH` when the `.c3l` directory is not at the source root.

### Target-specific dependencies

Add or remove a dependency for a specific target with:

```sh
--for-target TARGET
```

Inspect dependencies with:

```sh
c3pm dep list
c3pm dep list --for-target server
```

### Remove a dependency

```sh
c3pm dep remove NAME
```

Example:

```sh
c3pm dep remove sqlite3
```

Removing a direct dependency recalculates reachability and prunes generated C3 nodes and source inputs that are no longer needed. Shared transitive dependencies remain when another dependency still references them.

## Native libraries and linked C3 projects

Use `c3pm link` when a project needs a native package, an imported Nix package, or a static/dynamic target from another C3 project.

### Link a package from nixpkgs

```sh
c3pm link add sqlite3 --nix-package sqlite --runtime
```

### Link a local Nix package definition

```sh
c3pm link add custom --nix-package path:./nix/custom.nix
```

A `path:` Nix file is imported with an explicit `pkgs` argument instead of being resolved as a nixpkgs attribute.

### Link another C3 project

```sh
c3pm link add protocol \
  --source git+ssh://git@example.com/acme/protocol.git \
  --rev v1.0.0 \
  --c3c-target protocol-static \
  --passthrough \
  --for-target server
```

Important defaults and rules:

- `--c3c-target none` is the default;
- `--runtime` is the default link mode;
- a selected C3 target must be `static-lib` or `dynamic-lib`;
- runtime links are private Nix inputs;
- passthrough links become propagated Nix inputs;
- `--subdir PATH` selects a project directory inside the fetched source.

When a link has its own fetched source, this:

```text
--nix-package path:./package.nix
```

resolves inside that source and is evaluated as:

```nix
import path { inherit pkgs; }
```

### List or remove links

```sh
c3pm link list
c3pm link list --for-target server
c3pm link remove sqlite3
```

For target-specific links, pass the same `--for-target TARGET` when removing the link.

## Synchronize the project

```sh
c3pm install
```

`install` synchronizes generated state with `project.json` and all reachable library manifests.

It:

- discovers transitive dependencies;
- validates Nix package attributes;
- preserves already locked references;
- generates the C3 library tree under `lib/*.c3l`;
- updates `.c3pm/nix/` atomically.

Run it after manually editing project or library metadata.

Running `c3pm install` repeatedly with unchanged inputs is safe and reuses `.c3pm/nix/flake.lock`.

## Development shell

Start an interactive shell:

```sh
c3pm shell
```

Or run a single command inside the project environment:

```sh
c3pm shell -- c3c build
c3pm shell -- c3c test
c3pm shell -- ./build/my_app
```

`c3pm shell` runs `install` first, then enters the locked Nix environment containing:

- `c3c`;
- declared native packages;
- compiler and linker configuration;
- the complete generated `lib/*.c3l` tree.

## Portable bundles

For a project with exactly one executable target:

```sh
c3pm bundle
```

For a project with multiple executable targets:

```sh
c3pm bundle server
```

Choose a custom output path with:

```sh
c3pm bundle server --output ./release/backend
```

The default output is:

```text
dist/<target>
```

`bundle` supports executable targets only. The result is a regular Linux executable, not a symlink into the Nix store.

Nix determines the package's referenced runtime closure, then the pinned nix-portable `zstd-fast` bundler embeds that closure into the output file.

## Metadata reference

In normal use, prefer the `dep`, `link`, and `toolchain` commands instead of editing metadata manually. Their changes are transactional and preserve JSONC comments.

### Dependency metadata

Projects and `.c3l` manifests use:

- `vendor.c3pm.c3.dependencies` for C3 source declarations;
- `vendor.c3pm.nix` for native inputs.

Projects may also declare `toolchain` and `links`. Library manifests must include the standard C3 `provides` field.

Canonical dependency metadata:

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

Source declarations are flat objects.

| `source` | Location fields | Other required fields |
| --- | --- | --- |
| `github` | `owner`, `repository` | `rev` |
| `git+https` | `url` beginning with `https://` | `rev` |
| `git+ssh` | `url` beginning with `ssh://` | `rev` |
| `archive+https` | `url` beginning with `https://` | `sha256` in SRI form |
| `path` | `path` | none |

`subdir` is optional for every source type. Only these flat source-object forms are supported.

### Link metadata

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

## Lock file

c3pm uses a single dependency lock database:

```text
.c3pm/nix/flake.lock
```

It pins:

- nixpkgs;
- nix-portable;
- every fetched C3 source.

c3pm delegates fetching and locking to Nix instead of cloning repositories itself or maintaining a second lock format.

For real-world library-native Nix metadata, see:

[SMFloris/c3c-vendor](https://github.com/SMFloris/c3c-vendor/tree/c3pm/libraries)

## Native dependencies and Nix

C3 metadata and Nix metadata serve different purposes.

### C3 metadata describes what the compiler needs

```json
{
  "dependencies": ["sqlite3"],
  "linked-libraries": ["sqlite3"]
}
```

This tells C3 which libraries and linker names to use.

### Nix metadata describes what the build environment needs

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

The package classes are:

| Field | Purpose |
| --- | --- |
| `nativeBuildInputs` | Tools executed during the build, such as `pkg-config`, CMake, or code generators |
| `buildInputs` | Libraries and headers compiled or linked into the target, such as SQLite, OpenSSL, zlib, or SDL |
| `propagatedNativeBuildInputs` | Build tools that consumers of a packaged library must also receive |
| `propagatedBuildInputs` | Libraries that consumers inherit when using a packaged library |

Entries are nixpkgs attribute paths, not arbitrary Nix expressions. Both simple and nested attributes are supported:

```json
{
  "buildInputs": [
    "openssl",
    "xorg.libX11",
    "llvmPackages.clang"
  ]
}
```

c3pm validates these attributes against the locked nixpkgs revision and emits references such as `pkgs.openssl` and `pkgs.xorg.libX11`.

It gathers all four input classes from the root project and every reachable C3 dependency, deduplicates them, and provides the result to both the development shell and project builder.

### Linker names are not nixpkgs package names

c3pm deliberately does not guess a nixpkgs package from a C3 linker name.

For example:

```json
"linked-libraries": ["sqlite3"]
```

means “pass `sqlite3` to the C3 linker,” while:

```json
"buildInputs": ["sqlite"]
```

means “make the nixpkgs `sqlite` package available to the build.”

Library authors should declare both when both are required.

### Native packages outside nixpkgs

Projects and library manifests can load trusted package definitions through `vendor.c3pm.nix.imports`:

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

Each import:

- must be a relative `.nix` path;
- is resolved from the declaring project or `.c3l` directory;
- is evaluated with `pkgs.callPackage`;
- is added to `buildInputs`.

Absolute paths and paths containing `..` are rejected.

Unlike generated dependency nodes, declared imports are trusted executable Nix code.

## How portable bundles work

For an executable target, c3pm asks Nix to build a normal package whose primary program is:

```text
$out/bin/<target>
```

Nix then determines every Nix-store path referenced by the finished package, including transitive shared libraries.

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

c3pm does **not**:

- assume `buildInputs` are the runtime dependency set;
- run `ldd` to discover libraries;
- copy `.so` files manually;
- patch ELF paths.

Instead, the pinned nix-portable bundler embeds the built package and its runtime closure, then provides a virtual `/nix/store` environment when the resulting executable starts.

The result can run without system copies of SQLite, OpenSSL, Nix, or c3pm.

A portable bundle is not necessarily a statically linked ELF binary. Dynamically linked libraries may still exist inside the embedded Nix closure. Here, **portable** means the single output file carries everything the packaged program references.

## Build c3pm from source

With C3 0.8.3 installed:

```sh
c3c build
c3c test
./build/c3pm --help
```

Without a saved backend, a source build automatically uses `nix` from `PATH`.

Select a persistent backend with `c3pm toolchain nix use`, or use a one-command override in CI:

```sh
C3PM_NIX=nix ./build/c3pm install
C3PM_NIX=nix ./build/c3pm bundle
```

To select a specific nix-portable executable instead:

```sh
C3PM_NIX_PORTABLE=/path/to/nix-portable ./build/c3pm install
```

Released c3pm executables never embed Nix or nix-portable.

## License

MIT. See [LICENSE](LICENSE).
