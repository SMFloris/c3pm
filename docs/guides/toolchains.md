---
title: "Configure toolchains"
description: "Select the c3c compiler, pin nixpkgs, and choose a Nix backend."
permalink: /docs/guides/toolchains/
---

c3pm manages the C3 compiler and nixpkgs revision for each project. Each user selects their own Nix backend.

## C3 compiler

The default C3 version is **{{ site.c3_version }}**. Pin a version for the project, or reset it to the default:

```sh
c3pm toolchain c3c set {{ site.c3_version }}
c3pm toolchain c3c reset
```

Use the selected compiler inside the project environment:

```sh
c3pm shell -- c3c --version
```

c3pm locks `github:c3lang/c3c/v<VERSION>` as a source input, then overrides the nixpkgs C3 package with that version and source. Nix records the resolved source hash in [`.c3pm/nix/flake.lock`]({{ '/docs/reference/lock-file/' | relative_url }}).

## nixpkgs

Set, update, or reset the nixpkgs revision for the project:

```sh
c3pm toolchain nixpkgs set github:NixOS/nixpkgs/nixpkgs-unstable
c3pm toolchain nixpkgs update
c3pm toolchain nixpkgs reset
```

`update` refreshes the locked nixpkgs input without changing its configured reference. The [c3pm metadata reference]({{ '/docs/reference/metadata/#toolchain-metadata' | relative_url }}) describes the stored C3 and nixpkgs settings.

macOS Intel defaults to a pinned nixpkgs 26.05 revision because newer nixpkgs no longer supports `x86_64-darwin`; c3pm pins C3 0.8.4 there. Other platforms default to nixpkgs-unstable.

Inspect the project toolchain with:

```sh
c3pm toolchain show
```

## Nix backend

c3pm uses Nix to realize the project environment. If no backend is saved, c3pm uses the `nix` command in `PATH`.

```sh
c3pm toolchain nix status
c3pm toolchain nix use system
c3pm toolchain nix use portable
c3pm toolchain nix use /opt/nix/bin/nix
c3pm toolchain nix reset
```

The `portable` backend lets c3pm download and manage `nix-portable` on Linux x86_64 and ARM64. macOS requires system Nix. Backend selection is user configuration rather than project metadata, so backend commands also work outside a C3 project.

For one-off overrides:

```sh
C3PM_NIX=/path/to/nix c3pm install
C3PM_NIX_PORTABLE=/path/to/nix-portable c3pm install
```
