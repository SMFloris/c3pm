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

## Usage

Run `c3pm` from a directory containing `project.json`, or from one of its
subdirectories. c3pm discovers the project root automatically.

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

Projects and library manifests can declare trusted package definitions through
`vendor.c3pm.nix.imports`. Each import is a relative `.nix` path resolved from
the declaring project or `.c3l` directory and evaluated with `pkgs.callPackage`.
Absolute paths and paths containing `..` are rejected.

## Building c3pm from source

With C3 0.8.3 available:

```sh
c3c build
c3c test
./build/c3pm --help
```

## License

MIT. See [LICENSE](LICENSE).
