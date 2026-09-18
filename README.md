# c3pm — C3 Package Manager

`c3pm` is a Nix-backed package manager for C3 projects.

It reads the standard C3 dependency graph and adds `vendor.c3pm` metadata for sources, toolchains, and native packages. c3pm uses those inputs to create a reproducible development and build environment.

> [!WARNING]
> **Current supported platform: Linux x86_64.**

> [!NOTE]
> **Default nixpkgs target:** nixpkgs-unstable.
> **Default C3 target:** C3 0.8.4.

Released c3pm binaries are standalone static executables. Running c3pm itself does **not** require C3 or a compatible system libc. Nix remains a separate backend: c3pm can use your existing installation or manage `nix-portable` for you.

## Quick start

### 1. Install c3pm

Run the installer for the latest release:

```sh
curl --fail --location \
  https://github.com/SMFloris/c3pm/releases/latest/download/install.sh | sh -
```

### 2. Try the example project

Clone the repository, then run the SQLite todo example:

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

With the portable Nix backend, the first Nix operation initializes `nix-portable` and may fetch the inputs in [`.c3pm/nix/flake.lock`](#lock-file). Later commands reuse that store and lock.

## Command overview

Run c3pm from the directory containing `project.json` or from any directory below it. c3pm finds the project root automatically.

```text
c3pm dep <add|remove|list> ...
c3pm link <add|remove|list> ...
c3pm toolchain <show|c3c|nixpkgs|nix> ...
c3pm install
c3pm shell [-- COMMAND...]
c3pm bundle [TARGET] [--output PATH]
```

| Command | Purpose |
| --- | --- |
| [`c3pm dep`](#c3-dependencies) | Add, list, or remove C3 source dependencies. |
| [`c3pm link`](#linking-libraries-and-projects) | Manage native packages, Nix definitions, and linked C3 library targets. |
| [`c3pm toolchain`](#toolchain) | Pin C3 and nixpkgs, and select the user's Nix backend. |
| [`c3pm install`](#synchronize-the-project) | Resolve the dependency graph and synchronize generated project state. |
| [`c3pm shell`](#development-shell) | Enter the locked environment or run one command inside it. |
| [`c3pm bundle`](#portable-bundles) | Build a portable Linux executable. |

Most projects follow this workflow:

```text
configure toolchain → add dependencies/links → install → build/test in shell → bundle
```

## Toolchain

c3pm manages the C3 compiler and nixpkgs revision for each project. Each user selects their own Nix backend.

### C3 compiler

The default C3 version is **0.8.4**. Pin a version for the project, or reset it to the default:

```sh
c3pm toolchain c3c set 0.8.4
c3pm toolchain c3c reset
```

Use the selected compiler inside the project environment:

```sh
c3pm shell -- c3c --version
```

c3pm locks `github:c3lang/c3c/v<VERSION>` as a source input, then overrides the nixpkgs C3 package with that version and source. Nix records the resolved source hash in [`.c3pm/nix/flake.lock`](#lock-file).

### nixpkgs

Set, update, or reset the nixpkgs revision for the project:

```sh
c3pm toolchain nixpkgs set github:NixOS/nixpkgs/nixpkgs-unstable
c3pm toolchain nixpkgs update
c3pm toolchain nixpkgs reset
```

`update` refreshes the locked nixpkgs input without changing its configured reference. The [c3pm metadata reference](#toolchain-metadata) describes the stored C3 and nixpkgs settings.

Inspect the project toolchain with:

```sh
c3pm toolchain show
```

### Nix backend

c3pm uses Nix to realize the project environment. If no backend is saved, c3pm uses the `nix` command in `PATH`.

```sh
c3pm toolchain nix status
c3pm toolchain nix use system
c3pm toolchain nix use portable
c3pm toolchain nix use /opt/nix/bin/nix
c3pm toolchain nix reset
```

The `portable` backend lets c3pm download and manage `nix-portable`. Backend selection is user configuration rather than project metadata, so backend commands also work outside a C3 project.

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
4. records remote references in [`.c3pm/nix/flake.lock`](#lock-file).

Pass `--name NAME` to assert the expected `provides` value.

Supported source forms:

| Source | Required options | Use case |
| --- | --- | --- |
| `github:OWNER/REPO` | `--rev REF` | GitHub repository |
| `git+https://HOST/PATH` | `--rev REF` | Git over HTTPS |
| `git+ssh://HOST/PATH` | `--rev REF` | Git over SSH |
| `archive+https://HOST/PATH` | `--sha256 sha256-...` | Fixed-output archive |
| `path:PATH` | none | Local directory |

Pass `--subdir PATH` when the `.c3l` directory is below the source root.

### Target-specific dependencies

Add or remove a dependency for one target with:

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

Removing a direct dependency recalculates the graph and prunes generated C3 nodes and source inputs that are no longer reachable. A shared transitive dependency remains when another dependency still uses it.

## Linking libraries and projects

Use `c3pm link` to add a native package, an imported Nix package, or a static or dynamic library target from another C3 project.

### Link a package from nixpkgs

```sh
c3pm link add sqlite3 --nix-package sqlite --runtime
```

### Link a local Nix package definition

```sh
c3pm link add custom --nix-package path:./nix/custom.nix
```

c3pm imports a `path:` Nix file with an explicit `pkgs` argument instead of resolving it as a nixpkgs attribute.

### Link another C3 project

```sh
c3pm link add protocol \
  --source git+ssh://git@example.com/acme/protocol.git \
  --rev v1.0.0 \
  --c3c-target protocol-static \
  --passthrough \
  --for-target server
```

### Runtime and passthrough links

Both modes make the selected package or C3 library target available while c3pm builds the current project. The mode controls whether that Nix input stops at this project or passes to its consumers:

- `--runtime` keeps the input private to the current project. c3pm places the package in the generated Nix `buildInputs`. Use this mode for an application dependency or an implementation detail that downstream projects do not need.
- `--passthrough` passes the input to consumers. c3pm places the package in `propagatedBuildInputs`, so projects that consume this project also receive it. Use this mode when a library exposes the dependency through its public API or requires consumers to link it.

For example, an application that uses SQLite internally should normally choose `--runtime`. A reusable C3 library whose public API exposes types or symbols from another native library should normally choose `--passthrough`.

These modes do not select static or dynamic linking, and they do not change the name c3c passes to the linker. `--c3c-target` selects a `static-lib` or `dynamic-lib` target. `--runtime` and `--passthrough` control only Nix dependency propagation.

Important defaults and rules:

- `--c3c-target none` is the default;
- `--runtime` is the default link mode;
- a selected C3 target must be `static-lib` or `dynamic-lib`;
- `--subdir PATH` selects a project directory inside the fetched source.

For a link with its own fetched source, this option:

```text
--nix-package path:./package.nix
```

resolves inside the fetched source and evaluates as:

```nix
import path { inherit pkgs; }
```

### List or remove links

```sh
c3pm link list
c3pm link list --for-target server
c3pm link remove sqlite3
```

To remove a target-specific link, pass the same `--for-target TARGET` used to add it.

## Synchronize the project

```sh
c3pm install
```

`install` synchronizes the generated state with `project.json` and every reachable library manifest.

It:

- discovers transitive dependencies;
- validates Nix package attributes;
- preserves already locked references;
- generates the C3 library tree under `lib/*.c3l`;
- updates `.c3pm/nix/` atomically.

Run it after editing project or library metadata by hand.

It is safe to run `c3pm install` repeatedly. Unchanged inputs reuse [`.c3pm/nix/flake.lock`](#lock-file).

## Development shell

Start an interactive shell:

```sh
c3pm shell
```

Run a single command without opening an interactive shell:

```sh
c3pm shell -- c3c build
c3pm shell -- c3c test
c3pm shell -- ./build/my_app
```

`c3pm shell` runs `install` first, then enters the locked Nix environment with:

- a `(c3pm)` prompt prefix so the active environment is visible;
- `c3c`;
- declared native packages;
- compiler and linker configuration;
- the complete generated `lib/*.c3l` tree.

## Portable bundles

For a project with one executable target:

```sh
c3pm bundle
```

For a project with multiple executable targets, name the target:

```sh
c3pm bundle server
```

Set a custom output path with:

```sh
c3pm bundle server --output ./release/backend
```

The default output is:

```text
dist/<target>
```

`bundle` supports executable targets only. Its output is a regular Linux executable rather than a symlink into the Nix store.

[How portable bundles work](#how-portable-bundles-work) explains how Nix finds the package's referenced runtime closure and how the pinned nix-portable `zstd-fast` bundler embeds it in the output file.

## Installer reference

### Install location

c3pm installs to this directory by default:

```text
$HOME/.local/bin/c3pm
```

### Installer behavior

The installer does the following:

- supports Linux x86_64;
- installs missing bootstrap tools when needed;
- downloads and verifies the latest c3pm release;
- reuses an existing Nix installation when available;
- otherwise chooses a suitable Nix setup automatically.

On a compatible systemd host, the installer prefers the multi-user Nix daemon. On other hosts it uses a single-user installation. A root environment without a compatible daemon uses `nix-portable`.

### Options

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

Every option also has an environment-variable equivalent. The installer can bootstrap packages through `apt`, `dnf`/`yum`, `pacman`, `zypper`, or `apk`.

Release checksums are verified before an existing c3pm binary is replaced.

## Project and library files

For normal use, prefer the `dep`, `link`, and `toolchain` commands over manual metadata edits. These commands apply changes transactionally and preserve JSONC comments.

### Projects and libraries

c3pm reads two kinds of C3 metadata file. They share the same dependency and native-input formats, but describe different parts of the graph:

| File | Describes | Identity and ownership |
| --- | --- | --- |
| `project.json` | The root project, its build targets, and direct dependencies | Does not require `provides`; owns the c3pm `toolchain` and `links` settings |
| `.c3l/manifest.json` | One reusable C3 library and the requirements inherited by its consumers | Must declare `provides`; carries the library's C3 dependencies and native inputs |

Both files can carry c3pm-specific settings under `vendor.c3pm`. See the [c3pm metadata reference](#c3pm-metadata-reference) for the shared dependency and Nix fields and the project-only toolchain settings.

### Project metadata

The standard `dependencies` array tells c3c which C3 libraries the project uses. See the [c3pm metadata reference](#c3pm-metadata-reference) for the `vendor.c3pm` fields in this example.

This complete `project.json` example declares SQLite as both a C3 dependency and a native build input:

```json
{
  "dependencies": ["sqlite3"],
  "dependency-search-paths": ["lib"],
  "vendor": {
    "c3pm": {
      "toolchain": {
        "c3c": "0.8.4",
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
      },
      "nix": {
        "nativeBuildInputs": ["pkg-config"],
        "buildInputs": ["sqlite"]
      }
    }
  }
}
```

### C3 library metadata

A library manifest describes one `.c3l` package. Its required `provides` value is the package name used in dependency lists. The library's own C3 dependencies and native inputs become part of the graph whenever a project can reach that library. See the [c3pm metadata reference](#c3pm-metadata-reference) for the shared `vendor.c3pm` fields.

This `.c3l/manifest.json` example provides the `sqlite3` C3 library, asks c3c to link `sqlite3`, and makes the nixpkgs `sqlite` package available:

```json
{
  "provides": "sqlite3",
  "dependencies": [],
  "linked-libraries": ["sqlite3"],
  "vendor": {
    "c3pm": {
      "nix": {
        "buildInputs": ["sqlite"]
      }
    }
  }
}
```

## c3pm metadata reference

All c3pm-specific metadata lives under `vendor.c3pm`. The same field has the same meaning wherever it is valid:

| Field | Purpose | Used by |
| --- | --- | --- |
| `c3.dependencies` | Maps C3 dependency names to their source locations | Projects and library manifests |
| `nix` | Declares native tools, libraries, propagated inputs, and local package definitions | Projects and library manifests |
| `toolchain` | Pins the C3 compiler and nixpkgs reference | Projects |
| `links` | Connects project targets to native packages or other C3 project targets | Projects |

### C3 dependency sources

Each entry under `vendor.c3pm.c3.dependencies` is a flat source object:

| `source` | Location fields | Other required fields |
| --- | --- | --- |
| `github` | `owner`, `repository` | `rev` |
| `git+https` | `url` beginning with `https://` | `rev` |
| `git+ssh` | `url` beginning with `ssh://` | `rev` |
| `archive+https` | `url` beginning with `https://` | `sha256` in SRI form |
| `path` | `path` | none |

`subdir` is optional for every source type. These are the only supported source-object forms.

### Toolchain metadata

`vendor.c3pm.toolchain.c3c` stores the project compiler version. `vendor.c3pm.toolchain.nixpkgs` stores the nixpkgs source reference. These fields belong to `project.json`; use the [toolchain commands](#toolchain) to inspect or change them.

### Link metadata

A link connects a C3 target to an input that it must compile or link against. The input may be a native nixpkgs package, a custom Nix package, or a static or dynamic library target from another C3 project. A C3 dependency supplies source modules imported by name; a link supplies build or linker inputs.

See [Linking libraries and projects](#linking-libraries-and-projects) for the commands that create, inspect, and remove links.

`linked-libraries` gives c3c the library names to pass to the linker. It is the project-file equivalent of c3c's `-l` option. `linker-search-paths` gives the linker its search directories and corresponds to `-L`:

```json
{
  "linked-libraries": ["sqlite3"],
  "linker-search-paths": ["/path/to/lib"]
}
```

This is roughly equivalent to:

```sh
c3c ... -L /path/to/lib -l sqlite3
```

The name `sqlite3` is neither a nixpkgs package name nor a file path. The linker searches its configured directories for the platform's matching file, such as `libsqlite3.so` or `libsqlite3.a` on Linux.

c3pm adds the link name to `linked-libraries` at either the project or target level. Separately, it places the selected Nix package in the generated `buildInputs`. Inside `c3pm shell` and the bundle build, Nix exposes the package's library directories to the compiler and linker. Projects therefore do not normally need Nix-store paths in `linker-search-paths`.

Links live beside `c3`, `nix`, and `toolchain`. In this example, the `server` target links against `protocol`. c3pm fetches the remote project, builds `protocol-static`, imports the local Nix package definition, and propagates the result only to `server`:

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

### Nix inputs

C3 and Nix metadata answer different questions.

#### C3 metadata describes what the compiler needs

```json
{
  "dependencies": ["sqlite3"],
  "linked-libraries": ["sqlite3"]
}
```

This tells C3 which source libraries and linker names the project uses.

#### Nix metadata describes what the build environment needs

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

Each entry is a nixpkgs attribute path rather than an arbitrary Nix expression. Both simple and nested attributes are valid:

```json
{
  "buildInputs": [
    "openssl",
    "xorg.libX11",
    "llvmPackages.clang"
  ]
}
```

c3pm validates each attribute against the locked nixpkgs revision and emits references such as `pkgs.openssl` and `pkgs.xorg.libX11`.

c3pm gathers all four input classes from the root project and every reachable C3 dependency. It removes duplicates and provides the result to the development shell and project builder.

#### Linker names are not nixpkgs package names

c3pm does not guess a nixpkgs package from a C3 linker name.

For example:

```json
"linked-libraries": ["sqlite3"]
```

means “pass `sqlite3` to the C3 linker,” while:

```json
"buildInputs": ["sqlite"]
```

means “make the nixpkgs `sqlite` package available to the build.”

Declare both fields when the library needs both.

#### Native packages outside nixpkgs

Projects and library manifests can load trusted package definitions with `vendor.c3pm.nix.imports`:

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

Unlike generated dependency nodes, each declared import is trusted executable Nix code.

## Lock file

c3pm keeps all dependency locks in one file:

```text
.c3pm/nix/flake.lock
```

It pins:

- nixpkgs;
- nix-portable;
- every fetched C3 source.

Nix handles fetching and locking. c3pm does not clone repositories itself or maintain a second lock format.

For real-world library-native Nix metadata, see:

[SMFloris/c3c-vendor](https://github.com/SMFloris/c3c-vendor/tree/c3pm/libraries)

## How portable bundles work

For an executable target, c3pm asks Nix to build a regular package with this primary program:

```text
$out/bin/<target>
```

Nix then finds every store path referenced by the finished package, including transitive shared libraries.

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

Instead, the pinned nix-portable bundler embeds the built package and its runtime closure. When the resulting executable starts, the bundler provides a virtual `/nix/store` environment.

The result can run without system copies of SQLite, OpenSSL, Nix, or c3pm.

A portable bundle is not necessarily a statically linked ELF binary. The embedded Nix closure may still contain dynamically linked libraries. Here, **portable** means that one output file carries everything referenced by the packaged program.

## Build c3pm from source

With C3 0.8.4 installed:

```sh
c3c build
c3c test
./build/c3pm --help
```

Without a saved backend, a source build uses the `nix` command in `PATH`.

Select a persistent backend with `c3pm toolchain nix use`, or override it for one CI command:

```sh
C3PM_NIX=nix ./build/c3pm install
C3PM_NIX=nix ./build/c3pm bundle
```

To use a specific nix-portable executable instead:

```sh
C3PM_NIX_PORTABLE=/path/to/nix-portable ./build/c3pm install
```

Released c3pm executables never embed Nix or nix-portable.

## License

MIT. See [LICENSE](LICENSE).
