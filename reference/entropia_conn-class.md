# entropia_conn class

A typed, read-only DBI connection to an EntropIA SQLite database.
Subclass of
[RSQLite::SQLiteConnection](https://rsqlite.r-dbi.org/reference/SQLiteConnection-class.html);
carries `path`, `mode`, `schema_version` and `schema_hash` attributes.
