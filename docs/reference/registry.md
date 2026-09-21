---
title: "Registry format"
description: "Directory layout and JSON fields for publishing packages in a c3pm registry."
permalink: /docs/reference/registry/
---

A registry is a directory of JSON files. It can be a local folder or the root of a GitHub, Git, or HTTPS archive source. For each `namespace/name`, keep one package file and one file per published version:

## Directory layout

```text
registry.json
index.json
packages/
  vendor/
    raylib/
      package.json
      5.json
      5.5.json
      6.json
```

## Registry metadata: registry.json

The registry's `registry.json` identifies the format and records when the index was generated:

```json
{
  "name": "example-registry",
  "version": 1,
  "generated": "2026-09-21T00:00:00Z"
}
```

## Search index: index.json

`index.json` contains one entry per package. Search reads this file from a local snapshot; `latest` must be one of the package's declared versions. Keep its description and tags aligned with `package.json` so search results reflect the package metadata.

```json
{
  "packages": [
    {
      "id": "vendor/raylib",
      "name": "raylib",
      "namespace": "vendor",
      "latest": "6",
      "description": "C3 bindings for raylib.",
      "tags": ["bindings", "graphics", "games", "raylib"]
    }
  ]
}
```

## Package metadata: package.json

`packages/vendor/raylib/package.json` describes the package and lists every available version. The `id` must be `namespace/name`. `description`, `homepage`, and `repository` are required strings (they may be empty); `tags` is an array of strings; `versions` must be a nonempty array of unique strings. Version labels can follow the upstream package's numbering, such as `5`, `5.5`, and `6`; they do not have to be three-part SemVer strings. Users can select an exact label with `c3pm dep add vendor/raylib@5.5`.

```json
{
  "id": "vendor/raylib",
  "name": "raylib",
  "namespace": "vendor",
  "description": "C3 bindings for raylib.",
  "homepage": "https://www.raylib.com/",
  "repository": "https://github.com/SMFloris/c3c-vendor",
  "tags": ["bindings", "graphics", "games", "raylib"],
  "versions": ["6", "5.5", "5"]
}
```

## Version manifest: `<version>.json`

Each version needs a matching `<version>.json` file. For example, `packages/vendor/raylib/6.json` points to the `.c3l` directory that actually provides the C3 library:

```json
{
  "name": "raylib",
  "namespace": "vendor",
  "version": "6",
  "provides": "raylib6",
  "download": {
    "source": "github",
    "owner": "SMFloris",
    "repository": "c3c-vendor",
    "rev": "3ef0f672970b9bb6a9549470470d37ae25ba55c7",
    "subdir": "libraries/raylib6.c3l"
  },
  "toolchain": { "c3c": ">=0.8.1 <0.9.0" },
  "published": "2026-09-18T20:41:02Z"
}
```

## Source and compatibility fields

`provides` must match the `provides` value in that library's `manifest.json`; it can differ from the registry package name. `download` uses the same [source-object forms]({{ '/docs/reference/metadata/#c3-dependency-sources' | relative_url }}) as `vendor.c3pm.c3.dependencies`: `github`, `git+https`, `git+ssh`, `archive+https`, or `path`. Git sources need `rev`; HTTPS archives need an SRI `sha256` value; `subdir` is optional. `toolchain.c3c` is the declared compiler compatibility range, and `published` is an ISO-8601 timestamp. The current client checks that these two fields are present but does not evaluate the compiler range or timestamp format.

## Publish and validate

To publish a new version, add its version manifest, add the version to `package.json`, and update `index.json` if `latest` changes. Create a new package by adding all three entries. Check a local registry with `c3pm registry add local path:/absolute/path/to/registry`; this validates every indexed package and every listed version before saving it. After changing an already configured registry, run `c3pm registry update local` to refresh its validated search index. A remote registry needs a Git reference or archive hash when added, as shown in [Registries]({{ '/docs/guides/registries/' | relative_url }}).
