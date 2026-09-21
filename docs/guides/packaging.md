---
title: "Package C3 libraries"
description: "Prepare C3 libraries and bindings for direct use or registry releases."
permalink: /docs/guides/packaging/
---

A C3 package starts with a `.c3l` directory containing a `manifest.json` and the C3 source or interface files it provides. The manifest's `provides` name is the dependency name that projects use. Add C3 dependencies and native inputs to the manifest when consumers need them; see [Project and library manifests]({{ '/docs/reference/manifests/' | relative_url }}).

```text
raylib55.c3l/
  manifest.json
  raylib.c3i
  raylib.nix  # optional native-library definition
```

## Bindings (.c3l)

For a binding to another library, use a three-part release version: **major.minor matches the library version; patch tracks the binding release**. For example, a first C3 binding for raylib 5.5 is `5.5.0`. A correction to the C3 binding that still targets raylib 5.5 becomes `5.5.1`. A binding for raylib 6.0 starts at `6.0.0`.

This is a publishing convention, not a version constraint enforced by c3pm. Existing registries may use upstream labels such as `5.5`; `c3pm dep add raylib@5.5` selects that exact published label. Keep the library's actual upstream version clear in the package description when it differs from your binding release version.

The `.c3l/manifest.json` declares the C3 name through `provides`. It can also describe native libraries that consumers must link. For example, the [SQLite binding manifest]({{ '/docs/reference/manifests/#c3-library-metadata' | relative_url }}) links `sqlite3` and requests the nixpkgs `sqlite` package.

## When to include a Nix file

A binding may need more than C3 interface files: its consumers also need the matching native library, headers, and linker inputs. If the right version and build configuration are already available in nixpkgs, name that package in `vendor.c3pm.nix.buildInputs` in `manifest.json`; no separate `.nix` file is needed. A pure C3 library needs neither a native package nor a Nix file.

Include a `.nix` file when the binding needs a custom native package definition—for example, to pin a particular upstream release, apply a patch, or set build options that the nixpkgs package does not provide. The raylib binding uses one to build the raylib version that matches its C3 interface. Declare the file in the library manifest so c3pm loads it and adds the resulting package to the build inputs:

```json
{
  "vendor": {
    "c3pm": {
      "nix": {
        "imports": ["./raylib.nix"]
      }
    }
  }
}
```

The path is relative to the `.c3l` directory, so the definition travels with the binding. c3pm evaluates imported Nix code when the package is used; publish only definitions you trust. See [Native packages outside nixpkgs]({{ '/docs/reference/metadata/#native-packages-outside-nixpkgs' | relative_url }}) for the import rules.

## Publish a version

Publish the `.c3l` directory in a Git repository or another supported source and pin a release tag or commit. Consumers can then add it **directly**, or you can list that source as a version in a **registry**. The binding files can be the same in both cases.

### Direct use

Share the source location, pinned revision, and path to the `.c3l` directory. For example, a consumer can add a GitHub release directly:

```sh
c3pm dep add github:YOUR_ORG/YOUR_REPO \
  --rev v5.5.0 \
  --subdir libraries/raylib55.c3l
```

No registry entry is required. Direct dependencies are identified by their source and revision, not a registry version label; updating one requires an explicit new revision (or a new hash for an archive). See [Adding directly]({{ '/docs/guides/packages/#adding-directly' | relative_url }}).

### Registry release

To make the release searchable and installable by name and version, add a version manifest such as `packages/vendor/raylib/5.5.0.json` to a registry. Set its `download` source to the pinned release, its `subdir` to the binding directory, and its `provides` value to the `.c3l` manifest's `provides`. Add `5.5.0` to the package's `package.json` `versions` array, and update `index.json` if its `latest` changes. Every published version needs its own version manifest.

See the [Registry format reference]({{ '/docs/reference/registry/' | relative_url }}) for the JSON schema and validation workflow. After users refresh the registry index, they can discover and select the release:

```sh
c3pm show vendor/raylib
c3pm dep add vendor/raylib@5.5.0
```
