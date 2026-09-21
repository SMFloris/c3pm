---
title: "Lock file"
description: "How c3pm records reproducible source and toolchain inputs in flake.lock."
permalink: /docs/reference/lock-file/
---

c3pm keeps all dependency locks in one file:

```text
.c3pm/nix/flake.lock
```

It pins:

- nixpkgs;
- explicitly selected compiler inputs;
- fetched C3 dependencies and linked project sources.

Nix handles fetching and locking. c3pm does not clone repositories itself or maintain a second lock format.

The user's choice of system Nix or `nix-portable` is configured separately from the project lock. See [Configure toolchains]({{ '/docs/guides/toolchains/#nix-backend' | relative_url }}).

For real-world library-native Nix metadata, see:

[SMFloris/c3c-vendor](https://github.com/SMFloris/c3c-vendor/tree/c3pm/libraries)
