# Connect to an EntropIA SQLite database (read-only)

Opens `path` as a read-only DBI connection. The returned object is an
`entropia_conn`: a typed subclass of
[RSQLite::SQLiteConnection](https://rsqlite.r-dbi.org/reference/SQLiteConnection-class.html)
carrying the `path`, `mode`, `schema_version` and `schema_hash`
attributes. All DBI and dbplyr functions keep working on it.

## Usage

``` r
entropia_connect(path, write = FALSE, validate = TRUE, quiet = FALSE)
```

## Arguments

- path:

  Path to the EntropIA SQLite database, or `":memory:"`.

- write:

  Must be `FALSE` in v1 (read-only). Passing `TRUE` errors with class
  `entropia_error_write_disabled` and v2 guidance.

- validate:

  Logical. When `TRUE` (default) the connection runs a lightweight
  sanity query (rejecting files that are not readable SQLite databases)
  and applies the schema compatibility policy controlled by
  `options(entropiaR.schema_policy)`.

- quiet:

  Logical. When `TRUE`, suppresses the schema-policy warning emitted on
  open (only affects the default `"warn"` policy; errors are never
  silenced).

## Value

An `entropia_conn` object (S4, `SQLiteConnection` subclass).

## Examples

``` r
con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
  package = "entropiaR"
))
entropia_status(con)
#> entropiaR status
#>   path:           /home/runner/work/_temp/Library/entropiaR/extdata/entropia-example.sqlite
#>   mode:           read-only
#>   schema version: 0029_rag_chunks
#>   valid:          TRUE
#>   row counts:     _migrations=29, sync_meta=8, assets=5, entities=4, app_settings=3 (+26 more)
#>   sync:           last_sync_at 2026-01-15 12:13:20, capture_enabled TRUE
#>   journal:        delete
#>   wal sidecar:    FALSE
entropia_disconnect(con)
```
