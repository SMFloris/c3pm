---
title: "Create portable bundles"
description: "Package a C3 application and its runtime dependencies as one Linux executable."
permalink: /docs/guides/bundles/
---

For a project with one executable target:

```sh
c3pm bundle
```

For a project with multiple executable targets, name the target:

```sh
c3pm bundle server
```

Set a custom output path with:

```sh
c3pm bundle server --output ./release/backend
```

The default output is:

```text
dist/<target>
```

`bundle` supports executable targets only. Its output is a regular Linux executable rather than a symlink into the Nix store.

[How portable bundles work]({{ '/docs/internals/bundles/' | relative_url }}) explains how Nix finds the package's referenced runtime closure and embeds it in the output file.
