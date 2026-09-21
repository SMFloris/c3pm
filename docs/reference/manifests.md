---
title: "Project and library manifests"
description: "Understand project.json and .c3l/manifest.json files used by c3pm."
permalink: /docs/reference/manifests/
---

For normal use, prefer the `dep`, `link`, and `toolchain` commands over manual metadata edits. These commands apply changes transactionally and preserve JSONC comments.

## Projects and libraries

c3pm reads two kinds of C3 metadata file. They share the same dependency and native-input formats, but describe different parts of the graph:

| File | Describes | Identity and ownership |
| --- | --- | --- |
| `project.json` | The root project, its build targets, and direct dependencies | Does not require `provides`; owns the c3pm `toolchain` and `links` settings |
| `.c3l/manifest.json` | One reusable C3 library and the requirements inherited by its consumers | Must declare `provides`; carries the library's C3 dependencies and native inputs |

Both files can carry c3pm-specific settings under `vendor.c3pm`. See the [c3pm metadata reference]({{ '/docs/reference/metadata/' | relative_url }}) for the shared dependency and Nix fields and the project-only toolchain settings.

## Project metadata

The standard `dependencies` array tells c3c which C3 libraries the project uses. See the [c3pm metadata reference]({{ '/docs/reference/metadata/' | relative_url }}) for the `vendor.c3pm` fields in this example.

This complete `project.json` example declares SQLite as both a C3 dependency and a native build input:

```json
{
  "dependencies": ["sqlite3"],
  "dependency-search-paths": ["lib"],
  "vendor": {
    "c3pm": {
      "toolchain": {
        "c3c": "{{ site.c3_version }}",
        "nixpkgs": "github:NixOS/nixpkgs/nixpkgs-unstable"
      },
      "c3": {
        "dependencies": {
          "sqlite3": {
            "source": "github",
            "owner": "SMFloris",
            "repository": "c3c-vendor",
            "rev": "c3pm",
            "subdir": "libraries/sqlite3.c3l"
          }
        }
      },
      "nix": {
        "nativeBuildInputs": ["pkg-config"],
        "buildInputs": ["sqlite"]
      }
    }
  }
}
```

## C3 library metadata

A library manifest describes one `.c3l` package. Its required `provides` value is the package name used in dependency lists. The library's own C3 dependencies and native inputs become part of the graph whenever a project can reach that library. See the [c3pm metadata reference]({{ '/docs/reference/metadata/' | relative_url }}) for the shared `vendor.c3pm` fields.

This `.c3l/manifest.json` example provides the `sqlite3` C3 library, asks c3c to link `sqlite3`, and makes the nixpkgs `sqlite` package available:

```json
{
  "provides": "sqlite3",
  "dependencies": [],
  "linked-libraries": ["sqlite3"],
  "vendor": {
    "c3pm": {
      "nix": {
        "buildInputs": ["sqlite"]
      }
    }
  }
}
```
