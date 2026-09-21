---
title: "Build and run"
description: "Synchronize C3 dependencies and build, test, or run inside the c3pm development shell."
permalink: /docs/guides/build/
---

## Synchronize the project

```sh
c3pm install
```

`install` synchronizes the generated state with `project.json` and every reachable library manifest.

It:

- discovers transitive dependencies;
- validates Nix package attributes;
- preserves already locked references;
- generates the C3 library tree under `lib/*.c3l`;
- updates `.c3pm/nix/` atomically.

Run it after editing project or library metadata by hand.

It is safe to run `c3pm install` repeatedly. Unchanged inputs reuse [`.c3pm/nix/flake.lock`]({{ '/docs/reference/lock-file/' | relative_url }}).

## Development shell

Start an interactive shell:

```sh
c3pm shell
```

Run a single command without opening an interactive shell:

```sh
c3pm shell -- c3c build
c3pm shell -- c3c test
c3pm shell -- ./build/my_app
```

`c3pm shell` runs `install` first, then enters the locked Nix environment with:

- a `(c3pm)` prompt prefix so the active environment is visible;
- `c3c`;
- declared native packages;
- compiler and linker configuration;
- the complete generated `lib/*.c3l` tree.
