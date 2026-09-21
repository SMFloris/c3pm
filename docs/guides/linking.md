---
title: "Link libraries and projects"
description: "Link native libraries, Nix packages, and C3 library targets with c3pm."
permalink: /docs/guides/linking/
---

Use `c3pm link` to add a native package, an imported Nix package, or a static or dynamic library target from another C3 project.

## Adding/linking system libraries

c3pm makes native libraries available through Nix packages in your project's build environment.

### From nixpkgs

```sh
c3pm link add sqlite3 --nix-package sqlite --runtime
```

### From a local Nix package definition

```sh
c3pm link add custom --nix-package path:./nix/custom.nix
```

c3pm imports a `path:` Nix file with an explicit `pkgs` argument instead of resolving it as a nixpkgs attribute.

## Adding/linking other C3 projects

Fetch a C3 project and select the library target to build and link:

```sh
c3pm link add protocol \
  --source git+ssh://git@example.com/acme/protocol.git \
  --rev v1.0.0 \
  --c3c-target protocol-static \
  --passthrough \
  --for-target server
```

The selected `--c3c-target` must be a `static-lib` or `dynamic-lib` target. It defaults to `none` when omitted. Use `--subdir PATH` if the project is below the source root.

For a link with its own fetched source, `--nix-package path:./package.nix` resolves inside that source and evaluates as:

```nix
import path { inherit pkgs; }
```

## Runtime and passthrough links

These modes apply to both system libraries and linked C3 projects. `--runtime` is the default. Both modes make the input available while c3pm builds the current project; the difference is whether consumers inherit it:

- `--runtime` keeps the input private to the current project. c3pm places the package in the generated Nix `buildInputs`. Use this mode for an application dependency or an implementation detail that downstream projects do not need.
- `--passthrough` passes the input to consumers. c3pm places the package in `propagatedBuildInputs`, so projects that consume this project also receive it. Use this mode when a library exposes the dependency through its public API or requires consumers to link it.

For example, an application that uses SQLite internally should normally choose `--runtime`. A reusable C3 library whose public API exposes types or symbols from another native library should normally choose `--passthrough`.

These modes do not select static or dynamic linking, and they do not change the name c3c passes to the linker. `--c3c-target` selects a `static-lib` or `dynamic-lib` target. `--runtime` and `--passthrough` control only Nix dependency propagation.

## List or remove links

```sh
c3pm link list
c3pm link list --for-target server
c3pm link remove sqlite3
```

To remove a target-specific link, pass the same `--for-target TARGET` used to add it.
