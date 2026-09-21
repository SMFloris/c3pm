---
title: "Portable bundle implementation"
description: "How Nix packages a C3 executable and its referenced runtime closure."
permalink: /docs/internals/bundles/
---

For an executable target, c3pm asks Nix to build a regular package with this primary program:

```text
$out/bin/<target>
```

Nix then finds every store path referenced by the finished package, including transitive shared libraries.

```text
C3 executable package
        ↓
Nix reference graph
        ↓
complete runtime closure
        ↓
Nix default bundler
        ↓
single portable Linux executable
```

c3pm does **not**:

- assume `buildInputs` are the runtime dependency set;
- run `ldd` to discover libraries;
- copy `.so` files manually;
- patch ELF paths.

Instead, `nix bundle` embeds the built package and its runtime closure. When the resulting executable starts, the default bundler provides the environment needed by those store paths.

The result can run without system copies of SQLite, OpenSSL, Git, Nix, or c3pm.
Git is not included unless the packaged application itself references it.

A portable bundle is not necessarily a statically linked ELF binary. The embedded Nix closure may still contain dynamically linked libraries. Here, **portable** means that one output file carries everything referenced by the packaged program.
