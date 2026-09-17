# c3pm - C3 Package Manager

`c3pm` is a C3 package manager backed by Nix. C3 metadata describes the logical
dependency graph, while `vendor.c3pm` attributes in both projects and libs, supply source and native-package metadata,
that c3pm uses to generate the deterministic Nix environment.

The bootstrap implementation is written in C3 and currently targets C3 0.8.3.
Linux x86_64 releases are distributed as single portable executables containing
c3pm, nix-portable, and their runtime closure. The host does not need a separate
Nix, nix-portable, c3pm, or C3 installation.

## Quickstart

Download the latest x86_64 release and put it on your user PATH:

```sh
wget \
  https://github.com/SMFloris/c3pm/releases/latest/download/c3pm-linux-x86_64 \
  -O c3pm
chmod +x c3pm
mkdir -p "$HOME/.local/bin"
mv c3pm "$HOME/.local/bin/c3pm"
export PATH="$HOME/.local/bin:$PATH"
```

Try the SQLite todo example:

```sh
git clone https://github.com/SMFloris/c3pm.git
cd c3pm/examples/sqlite-example

# Resolve the C3 graph, SQLite, nixpkgs, and the development environment.
c3pm install

# Build and run inside the locked development shell.
c3pm shell
> c3c build
> ./build/sqlite_example add "ship c3pm"
> ./build/sqlite_example list

# Produce dist/sqlite_example as one portable executable.
c3pm bundle
./dist/sqlite_example list
```

The first command initializes the embedded nix-portable runtime and may fetch
the inputs recorded in `.c3pm/nix/flake.lock`. Later commands reuse that store
and lock.

Source builds first look for an explicitly configured Nix backend. If no
configuration exists, c3pm automatically uses `nix` from `PATH`. When neither
is available, c3pm prints the setup commands described below.

## Usage

Run `c3pm` from a directory containing `project.json`, or from one of its
subdirectories. c3pm discovers the project root automatically.

### Configure Nix

Detect and save an existing `nix` executable from `PATH`:

```sh
c3pm nix setup
```

If Nix is not found, c3pm explains that you can install Nix and retry or use
the portable setup command.

If Nix is not installed, let c3pm download and select nix-portable:

```sh
c3pm nix setup --portable
```

This downloads the host-architecture nix-portable `v012` executable to
`$XDG_DATA_HOME/c3pm/nix-portable`. When `XDG_DATA_HOME` is unset, c3pm uses
`$HOME/.local/share/c3pm/nix-portable`.

To use an existing native Nix installation, provide either an executable name
on `PATH` or a path:

```sh
c3pm nix setup --path nix
c3pm nix setup --path /opt/nix/bin/nix
```

The selected backend is recorded in `$XDG_CONFIG_HOME/c3pm/config.json`, or
`$HOME/.config/c3pm/config.json` when `XDG_CONFIG_HOME` is unset. Setup works
outside a C3 project. A saved selection takes precedence over automatic `nix`
discovery; run either setup form again to change it.

For one-off overrides, `C3PM_NIX=/path/to/nix` selects a native Nix client and
`C3PM_NIX_PORTABLE=/path/to/nix-portable` selects a nix-portable launcher.
These environment variables take precedence over the saved configuration.

### Add a dependency

```sh
c3pm add github://OWNER@REPO[/PATH]#REF
```

For example:

```sh
c3pm add github://SMFloris@c3c-vendor/libraries/sqlite3.c3l#c3pm
```

`add` fetches the source through Nix, reads the selected `.c3l` manifest, and
uses its `provides` value as the dependency name. It updates `project.json`,
performs a full install, and preserves existing JSONC comments and formatting.
The optional path identifies a `.c3l` directory inside the repository. `REF`
may be a branch, tag, or commit and is resolved and locked by Nix.

### Remove a dependency

```sh
c3pm remove NAME
```

For example:

```sh
c3pm remove sqlite3
```

`remove` removes a direct project dependency, recalculates reachability, and
prunes generated C3 nodes and source inputs that are no longer needed. Shared
transitive dependencies remain available when another dependency still uses
them.

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

## Metadata and locking

The sole dependency lock database is `.c3pm/nix/flake.lock`. It pins nixpkgs,
nix-portable, and every fetched C3 source. c3pm does not clone sources,
calculate source hashes, or solve versions itself.

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
Configure a persistent native or portable backend with `c3pm nix setup`, or
use a one-command override in CI:

```sh
C3PM_NIX=nix ./build/c3pm install
C3PM_NIX=nix ./build/c3pm bundle
```

Set `C3PM_NIX_PORTABLE=/path/to/nix-portable` instead to select a particular
nix-portable bootstrap executable. Released bundles discover and use their
embedded Nix client automatically.

## License

MIT. See [LICENSE](LICENSE).
