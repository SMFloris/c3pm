---
title: "How c3pm works"
description: "Understand how C3 packages, native libraries, c3c, and Nix fit together."
permalink: /docs/getting-started/how-it-works/
---

c3pm manages a C3 project's libraries and build environment together. You declare what the project needs, then run c3c inside an environment containing those dependencies.

## C3 packages and native libraries

A C3 package provides source modules in a `.c3l` directory. A native library provides compiled code and headers, usually from nixpkgs. A binding such as `sqlite3` can require both: the C3 modules you import and the native SQLite library they call.

`c3pm add` manages C3 source dependencies. `c3pm link` connects native packages or another project's library target to your project. The names can differ: the C3 library is `sqlite3`, while its nixpkgs package is `sqlite`.

## Project metadata and the environment

Your `project.json` lists C3 dependencies and targets. Each library's `manifest.json` describes its own dependencies. Fields under `vendor.c3pm` supply source locations, native packages, and project toolchain settings.

Nix fetches those inputs and records resolved sources in `.c3pm/nix/flake.lock`. c3pm generates the library tree and the Nix configuration needed to build the project.

```text
project.json + library manifests
              ↓
C3 sources + native packages + toolchain
              ↓
locked development and build environment
              ↓
c3pm shell -- c3c run
```

## Everyday workflow

Search for a package, inspect it, and add it from your project:

```sh
c3pm search raylib
c3pm show raylib
c3pm add raylib
c3pm shell -- c3c run
```

`c3pm shell` synchronizes the project before starting the command. Run `c3pm install` directly when you only want to synchronize dependencies, or `c3pm bundle` to produce a portable executable.

Registry configuration and the chosen Nix backend are user settings. Dependencies, links, and compiler selections belong to the project. See [Project and library manifests]({{ '/docs/reference/manifests/' | relative_url }}) for the file formats.
