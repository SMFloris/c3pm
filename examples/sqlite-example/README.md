# SQLite todo example

This C3 CLI stores todo notes in `todos.db` through the `sqlite3.c3l` binding
from `SMFloris/c3c-vendor`. Its native SQLite dependency comes from the
library's `vendor.c3pm.nix.buildInputs` metadata.

From this directory:

```sh
c3pm install
c3pm shell -- c3c build
c3pm shell -- ./build/sqlite_example add "write an end-to-end test"
c3pm shell -- ./build/sqlite_example list
```

Build and run the portable executable without entering the development shell:

```sh
c3pm bundle
./dist/sqlite_example add "run the bundled app"
./dist/sqlite_example list
```

The generated bundle is a regular executable containing its SQLite runtime
closure. Neither Nix nor c3pm needs to be installed on the machine running it.
