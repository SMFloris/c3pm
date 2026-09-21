---
title: "Package C3 libraries"
description: "Prepare .c3l libraries and bindings for use in c3pm registries."
permalink: /docs/guides/packaging/
---

A C3 package starts with a `.c3l` directory containing a `manifest.json` and the C3 source or interface files it provides. The manifest's `provides` name is the dependency name that projects use. Add C3 dependencies and native inputs to the manifest when consumers need them; see [Project and library manifests]({{ '/docs/reference/manifests/' | relative_url }}).

```text
raylib55.c3l/
  manifest.json
  raylib.c3i
  raylib.nix
```

## Bindings (.c3l)

For a binding to another library, use a three-part release version: **major.minor matches the library version; patch tracks the binding release**. For example, a first C3 binding for raylib 5.5 is `5.5.0`. A correction to the C3 binding that still targets raylib 5.5 becomes `5.5.1`. A binding for raylib 6.0 starts at `6.0.0`.

This is a publishing convention, not a version constraint enforced by c3pm. Existing registries may use upstream labels such as `5.5`; `c3pm dep add raylib@5.5` selects that exact published label. Keep the library's actual upstream version clear in the package description when it differs from your binding release version.

The `.c3l/manifest.json` declares the C3 name through `provides`. It can also describe native libraries that consumers must link. For example, the [SQLite binding manifest]({{ '/docs/reference/manifests/#c3-library-metadata' | relative_url }}) links `sqlite3` and requests the nixpkgs `sqlite` package. If you import a local Nix definition, keep its path relative to the `.c3l` directory so it travels with the binding.

## Publish a version

Place the `.c3l` directory in a Git repository or another supported source. In your registry, add a version manifest named after the release, such as `packages/vendor/raylib/5.5.0.json`. Set its `download` source and `subdir` to the directory containing the binding, and set `provides` to the library manifest's value. Add `5.5.0` to `package.json`'s `versions` array; update `index.json`'s `latest` when appropriate.

Every version must have its own manifest. The source reference should identify the revision containing that binding release. See the [Registry format reference]({{ '/docs/reference/registry/' | relative_url }}) for the complete JSON schema and validation workflow. Once the registry is indexed, users can run `c3pm show vendor/raylib` to see releases and `c3pm dep add vendor/raylib@5.5.0` to select one.
