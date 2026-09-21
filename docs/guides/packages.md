---
title: "Search and add packages"
description: "Find C3 libraries, inspect their versions, and manage project dependencies."
permalink: /docs/guides/packages/
---

## Overview

A package is a reusable C3 library in a `.c3l` directory. Its manifest declares the library's name and any C3 or native dependencies it needs.

A registry is a catalog of packages, their versions, and where to fetch their source code. Packages are identified by `namespace/name`, such as `vendor/raylib`.

Search finds packages in your configured registries; `show` lists their versions. Adding a registry package selects its latest version unless you request an exact published version with `@VERSION`. c3pm uses Nix to fetch its source and resolve dependencies for your project. You can also add a repository, archive, or local directory directly, without a registry.

## Command aliases

{% include command-aliases.md %}

The examples below use the short commands.

## Searching for a package

Search by package name, description, or tag:

```sh
c3pm search raylib
c3pm search                         # List all packages
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

Choose a published version instead of `latest`:

```sh
c3pm dep add raylib@5.5
c3pm add vendor/raylib@5.5
```

The version must match an entry in the package's `versions` list exactly. For example, `5.5` and `5.5.0` are different version labels. The name alone works only when it is unique across all configured registries and namespaces. Run `c3pm registry update` to refresh available versions.

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
c3pm show raylib
```

The unqualified name works when the package name is unique across configured registries. Use `show` to find exact version labels before adding a specific version.

## Update a dependency

Update an installed registry package to a specific published version, or omit `@VERSION` to use the registry's latest:

```sh
c3pm dep update raylib@6
c3pm dep update raylib
```

The update replaces the dependency's pinned source in `project.json` and synchronizes the project. It also updates the release recorded under `vendor.c3pm.registry`. If the new release has a different C3 `provides` name, such as `raylib55` becoming `raylib6`, c3pm changes the dependency name in project targets too. Update your source imports to the new module name when needed.

For projects created before registry references were recorded, c3pm matches the installed source against published versions of the selected package. If it cannot identify one installed version unambiguously, it leaves the project unchanged.

## List dependencies and links

| Command | Shows |
| --- | --- |
| `c3pm list` | C3 dependencies and links |
| `c3pm dep list` | C3 dependencies only |
| `c3pm link list` | Links only |

For example, from a C3 project:

```sh
c3pm list
c3pm list --for-target server
c3pm dep list
c3pm link list
```

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
