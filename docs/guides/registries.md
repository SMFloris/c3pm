---
title: "Manage registries"
description: "Use the default catalog, add a team or local registry, and keep package search up to date."
permalink: /docs/guides/registries/
---

Registries tell c3pm where to find packages. Start with the default catalog, add your team's shared libraries, or try a registry you're building locally.

Registry settings are shared across your projects. You can run every command on this page outside a project.

## Start with the default registry

If you haven't configured a registry, your first search adds [the default catalog](https://github.com/SMFloris/c3pm-registry) automatically:

```sh
c3pm search raylib
c3pm registry list
```

The first setup fetches the catalog through Nix. Later searches use its local index. `registry list` shows your saved registry names and sources without accessing the network.

## Add your team's registry

Suppose your team keeps a registry in `acme/c3-registry` on GitHub. Give it a local name, then search just that catalog:

```sh
c3pm registry add team github:acme/c3-registry --rev main
c3pm search --registry team
```

`team` is your name for the registry; package IDs still use their own `namespace/name`. The `--rev` value selects a branch, tag, or commit. Add `--subdir PATH` if the registry lives below the repository root.

Other remote sources work too:

| Source | Required option |
| --- | --- |
| `git+https://HOST/PATH` | `--rev REF` |
| `git+ssh://git@HOST/PATH` | `--rev REF` |
| `archive+https://HOST/registry.tar.gz` | `--sha256` with the archive source's SRI hash |

Adding a registry validates its metadata and every listed package version before saving a searchable index. Remote sources use your configured Nix backend.

## Try a local registry

A folder is useful while preparing new packages or editing your catalog:

```sh
c3pm registry add local path:./my-registry
c3pm search --registry local
```

The folder must contain a valid [registry layout]({{ '/docs/reference/registry/' | relative_url }}). c3pm saves its absolute path, so it remains usable from other directories. After editing the files, run `c3pm registry update local` to refresh the search index.

## Pick up new packages and versions

Refresh one registry, or all of them:

```sh
c3pm registry update team
c3pm registry update
```

Each update rereads the configured source, validates it, and refreshes its index. A branch can pick up new commits; a pinned commit stays fixed. This updates package discovery, not dependencies already recorded in your projects.

To change a registry's source or revision, run `registry add` again with the same name and the new settings.

## Remove a registry

```sh
c3pm registry remove team
```

This removes the saved entry and its search index. Existing project dependencies and the registry's source files remain intact.

## Where to go next

Use [Search and add packages]({{ '/docs/guides/packages/' | relative_url }}) to install a library, or the [Registry format reference]({{ '/docs/reference/registry/' | relative_url }}) to publish your own catalog. The [CLI reference]({{ '/docs/reference/cli/#registries-and-search' | relative_url }}) lists all command options.

Registry settings are stored in `$XDG_CONFIG_HOME/c3pm/config.json`, or `~/.config/c3pm/config.json` by default, alongside your Nix backend selection.
