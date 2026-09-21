---
title: "CLI commands"
description: "Command syntax, aliases, and options for the c3pm C3 package manager."
permalink: /docs/reference/cli/
---

Run c3pm from the directory containing `project.json` or from any directory below it. c3pm finds the project root automatically.

`registry`, `search`, `show`, and `toolchain nix` also work outside a project.

## Command aliases

{% include command-aliases.md %}

## Commands

| Command | Purpose |
| --- | --- |
| `c3pm list` | List both C3 dependencies and links. |
| [`c3pm dep`]({{ '/docs/guides/packages/' | relative_url }}) | Add, list, or remove C3 source dependencies; inspect registry packages and versions. |
| [`c3pm link`]({{ '/docs/guides/linking/' | relative_url }}) | Manage native packages, Nix definitions, and linked C3 library targets. |
| [`c3pm registry`]({{ '/docs/guides/registries/' | relative_url }}) | Add, remove, update, or list package registries. |
| [`c3pm search`]({{ '/docs/guides/packages/#searching-for-a-package' | relative_url }}) | Search locally indexed registry packages. |
| [`c3pm toolchain`]({{ '/docs/guides/toolchains/' | relative_url }}) | Pin C3 and nixpkgs, and select the user's Nix backend. |
| [`c3pm install`]({{ '/docs/guides/build/#synchronize-the-project' | relative_url }}) | Resolve the dependency graph and synchronize generated project state. |
| [`c3pm shell`]({{ '/docs/guides/build/#development-shell' | relative_url }}) | Enter the locked environment or run one command inside it. |
| [`c3pm bundle`]({{ '/docs/guides/bundles/' | relative_url }}) | Build a portable Linux executable. |

Most projects follow this workflow:

```text
configure toolchain → add dependencies/links → install → build/test in shell → bundle
```

## Dependencies

```text
c3pm dep add SOURCE|[NAMESPACE/]NAME [--rev REF] [--sha256 HASH]
             [--subdir PATH] [--name NAME] [--for-target TARGET]
c3pm dep remove NAME [--for-target TARGET]
c3pm dep show [NAMESPACE/]NAME
c3pm dep list [--for-target TARGET]
```

For a direct source, `--rev` selects a Git reference, `--sha256` supplies an archive's SRI hash, and `--subdir` selects its library directory. Registry names use the published source declaration and do not accept these three overrides. `--name` asserts the expected manifest `provides` value. `--for-target` limits a dependency to one project target.

See [Search and add packages]({{ '/docs/guides/packages/' | relative_url }}) for accepted source forms and package-name resolution.

## List dependencies and links

| Command | Shows |
| --- | --- |
| `c3pm list` | C3 dependencies and links |
| `c3pm dep list` | C3 dependencies only |
| `c3pm link list` | Links only |

`c3pm list` is a combined listing command, not an alias. All three commands accept `--for-target TARGET`.

## Links

```text
c3pm link add NAME [--source SOURCE] [--rev REF] [--sha256 HASH]
              [--subdir PATH] [--c3c-target none|TARGET]
              [--nix-package PACKAGE] [--runtime|--passthrough]
              [--for-target TARGET]
c3pm link remove NAME [--for-target TARGET]
c3pm link list [--for-target TARGET]
```

`--nix-package` selects a nixpkgs attribute or a `path:` Nix definition. `--c3c-target` selects a fetched project's static or dynamic library target and defaults to `none`. `--runtime` is the default propagation mode; `--passthrough` passes the input to consumers. The two mode flags are mutually exclusive.

See [Link libraries and projects]({{ '/docs/guides/linking/' | relative_url }}) for examples and target-specific behavior.

## Registries and search

```text
c3pm registry add NAME SOURCE [--rev REF] [--sha256 HASH] [--subdir PATH]
c3pm registry remove NAME
c3pm registry update [NAME]
c3pm registry list
c3pm search [QUERY...] [--registry NAME] [--tag TAG]
```

`registry add` and `registry update` validate and index registries. With no name, `update` refreshes all configured registries. Search filters the local indexes by query words, registry name, and tag. See [Manage registries]({{ '/docs/guides/registries/' | relative_url }}).

## Toolchains

```text
c3pm toolchain show
c3pm toolchain c3c set VERSION
c3pm toolchain c3c reset
c3pm toolchain nixpkgs set REF
c3pm toolchain nixpkgs update
c3pm toolchain nixpkgs reset
c3pm toolchain nix status
c3pm toolchain nix use system|portable|PATH
c3pm toolchain nix reset
```

The compiler and nixpkgs settings belong to the project. Nix backend selection belongs to the user. See [Configure toolchains]({{ '/docs/guides/toolchains/' | relative_url }}), including the `C3PM_NIX` and `C3PM_NIX_PORTABLE` environment overrides.

## Build and ship

```text
c3pm install
c3pm shell [-- COMMAND...]
c3pm bundle [TARGET] [--output PATH]
```

`install` synchronizes generated dependencies and Nix state. `shell` synchronizes first, then opens an interactive shell or runs the command after `--`. `bundle` packages an executable target, writing `dist/<target>` unless `--output` is supplied.

## Help and version

| Command | Short form | Purpose |
| --- | --- | --- |
| `c3pm --help` | `c3pm -h` | Show the command summary |
| `c3pm --version` | `c3pm -V` | Show the installed version |
