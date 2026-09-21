---
title: "Search and add packages"
description: "Find C3 libraries, inspect their versions, and manage project dependencies."
permalink: /docs/guides/packages/
---

## Overview

A package is a reusable C3 library in a `.c3l` directory. Its manifest declares the library's name and any C3 or native dependencies it needs.

A registry is a catalog of packages, their versions, and where to fetch their source code. Packages are identified by `namespace/name`, such as `vendor/raylib`.

Search finds packages in your configured registries; `show` lists their versions. Adding a registry package selects its latest version and uses Nix to fetch its source and resolve dependencies for your project. You can also add a repository, archive, or local directory directly, without a registry.

## Command aliases

{% include command-aliases.md %}

The examples below use the short commands.

## Searching for a package

Search by package name, description, or tag:

```sh
c3pm search raylib
c3pm search                       # List all packages
c3pm search image --tag graphics
c3pm search raylib --registry default
```

If no registries are configured, the first search adds the default. Later searches work offline; run `c3pm registry update` to refresh results.

## Add a dependency

c3pm uses the library manifest's `provides` value as the dependency name. Pass `--name NAME` to assert an expected name.

### Adding from registry

Install the package's latest registered version:

```sh
c3pm add vendor/raylib
c3pm add raylib
```

The name alone works only when it is unique across all configured registries and namespaces. Run `c3pm registry update` to refresh available versions.

### Adding directly

Specify a repository, archive, or local directory:

```sh
c3pm add github:SMFloris/c3c-vendor \
  --rev c3pm \
  --subdir libraries/sqlite3.c3l
```

Supported source forms:

| Source | Required options | Use case |
| --- | --- | --- |
| `github:OWNER/REPO` | `--rev REF` | GitHub repository |
| `git+https://HOST/PATH` | `--rev REF` | Git over HTTPS |
| `git+ssh://HOST/PATH` | `--rev REF` | Git over SSH |
| `archive+https://HOST/PATH` | `--sha256 sha256-...` | Fixed-output archive |
| `path:PATH` | none | Local directory |

Pass `--subdir PATH` when the `.c3l` directory is below the source root.

Remote sources are fetched through Nix and recorded in [`.c3pm/nix/flake.lock`]({{ '/docs/reference/lock-file/' | relative_url }}).

## Show package versions

Inspect a registry package and all its available versions:

```sh
c3pm show vendor/raylib
```

You can also use `c3pm show raylib` when the package name is unique across configured registries.

## List dependencies and links

| Command | Shows |
| --- | --- |
| `c3pm list` | C3 dependencies and links |
| `c3pm dep list` | C3 dependencies only |
| `c3pm link list` | Links only |

All three accept `--for-target TARGET`. For `c3pm list`, the filter applies to both dependencies and links.

## Target-specific dependencies

Add or remove a dependency for one target with:

```sh
--for-target TARGET
```

Inspect dependencies with:

```sh
c3pm dep list
c3pm dep list --for-target server
```

## Remove a dependency

```sh
c3pm remove NAME
```

Example:

```sh
c3pm remove sqlite3
```

Removing a direct dependency recalculates the graph and prunes generated C3 nodes and source inputs that are no longer reachable. A shared transitive dependency remains when another dependency still uses it.
