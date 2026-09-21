---
title: "c3pm metadata"
description: "Source, toolchain, link, and native package fields under vendor.c3pm."
permalink: /docs/reference/metadata/
---

All c3pm-specific metadata lives under `vendor.c3pm`. The same field has the same meaning wherever it is valid:

| Field | Purpose | Used by |
| --- | --- | --- |
| `c3.dependencies` | Maps C3 dependency names to their source locations | Projects and library manifests |
| `nix` | Declares native tools, libraries, propagated inputs, and local package definitions | Projects and library manifests |
| `registry` | Records the registry, package ID, and selected version of a registry dependency | Projects |
| `toolchain` | Pins the C3 compiler and nixpkgs reference | Projects |
| `links` | Connects project targets to native packages or other C3 project targets | Projects |

## C3 dependency sources

Each entry under `vendor.c3pm.c3.dependencies` is a flat source object:

| `source` | Location fields | Other required fields |
| --- | --- | --- |
| `github` | `owner`, `repository` | `rev` |
| `git+https` | `url` beginning with `https://` | `rev` |
| `git+ssh` | `url` beginning with `ssh://` | `rev` |
| `archive+https` | `url` beginning with `https://` | `sha256` in SRI form |
| `path` | `path` | none |

`subdir` is optional for every source type. These are the only supported source-object forms.

## Registry references

When `c3pm dep add` installs a registry package, the project's `project.json` records the selected release under `vendor.c3pm.registry`. The entry key is the library manifest's `provides` name:

```json
{
  "vendor": {
    "c3pm": {
      "registry": {
        "raylib55": {
          "registry": "default",
          "package": "vendor/raylib",
          "version": "5.5"
        }
      }
    }
  }
}
```

`registry` is the configured registry name, `package` is its `namespace/name` ID, and `version` is the exact published label. c3pm also keeps the resolved source under `vendor.c3pm.c3.dependencies`, so existing builds remain pinned until `c3pm dep update` changes them. Removing the dependency removes this reference when no target still uses it. The library's own `.c3l/manifest.json` continues to describe what that library provides.

## Toolchain metadata

`vendor.c3pm.toolchain.c3c` stores the project compiler version. `vendor.c3pm.toolchain.nixpkgs` stores the nixpkgs source reference. These fields belong to `project.json`; use the [toolchain commands]({{ '/docs/guides/toolchains/' | relative_url }}) to inspect or change them.

## Link metadata

A link connects a C3 target to an input that it must compile or link against. The input may be a native nixpkgs package, a custom Nix package, or a static or dynamic library target from another C3 project. A C3 dependency supplies source modules imported by name; a link supplies build or linker inputs.

See [Linking libraries and projects]({{ '/docs/guides/linking/' | relative_url }}) for the commands that create, inspect, and remove links.

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

## Nix inputs

C3 and Nix metadata answer different questions.

### C3 metadata describes what the compiler needs

```json
{
  "dependencies": ["sqlite3"],
  "linked-libraries": ["sqlite3"]
}
```

This tells C3 which source libraries and linker names the project uses.

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

### Linker names are not nixpkgs package names

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

### Native packages outside nixpkgs

Projects and library manifests can load trusted package definitions with `vendor.c3pm.nix.imports`. Use an array of paths, or a single path string when there is only one definition:

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
