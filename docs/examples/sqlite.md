---
title: "SQLite application"
description: "Build a C3 SQLite todo application and package it as a portable executable."
permalink: /docs/examples/sqlite/
---

This example stores todo notes in `todos.db` using the `sqlite3` C3 binding. The binding's manifest supplies its native SQLite dependency through Nix.

Clone the repository, then open the included SQLite example:

```sh
git clone https://github.com/SMFloris/c3pm.git
cd c3pm/examples/sqlite-example

# Resolve C3 dependencies, SQLite, nixpkgs, and the dev environment.
c3pm install

# Build and run inside the locked environment.
c3pm shell -- c3c build
c3pm shell -- ./build/sqlite_example add "ship c3pm"
c3pm shell -- ./build/sqlite_example list

# On Linux only, produce one portable executable.
c3pm bundle
./dist/sqlite_example list
```

The [example source](https://github.com/SMFloris/c3pm/tree/main/examples/sqlite-example) is included in the c3pm repository.
