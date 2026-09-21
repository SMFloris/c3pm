---
title: "Dependency resolution and Nix"
description: "How c3pm resolves C3 library graphs and generates a locked Nix environment."
permalink: /docs/internals/dependency-resolution/
---

c3pm reads C3 metadata and generates Nix inputs and build expressions. Nix performs remote fetching, source locking, and builds.

## Resolve the library graph

Starting with the project's dependencies, c3pm reads each source's `.c3l/manifest.json`, checks its `provides` name, and discovers its dependencies. Discovery continues until every reachable library has been read. A dependency name cannot resolve to conflicting sources.

For a registry package, c3pm resolves the indexed `latest` version or an explicitly requested `@VERSION` to a concrete source declaration. The library manifest then supplies the dependency graph and native requirements.

The project records both the pinned source and its registry reference under `vendor.c3pm.registry`. `c3pm dep update` uses that reference to find the installed package and select a new release. Older projects without the reference are matched against published source declarations.

## Generate and validate the environment

The installer carries the existing lock into a staging directory at `.c3pm/nix.next/`. It generates the flake, package expressions, shell, and a dependency expression for each reachable library.

c3pm validates the declared nixpkgs attributes and the generated shell, then asks Nix to build the combined C3 library tree. After validation and building succeed, it replaces `.c3pm/nix/` with the staged configuration and updates the library links under `lib/`.

## Reuse locked inputs

Ordinary synchronization preserves already locked references. `c3pm toolchain nixpkgs update` explicitly refreshes nixpkgs; removing a dependency prunes generated nodes and inputs that are no longer reachable.

See [Lock file]({{ '/docs/reference/lock-file/' | relative_url }}) for stored state and [c3pm metadata]({{ '/docs/reference/metadata/' | relative_url }}) for source and Nix input fields.
