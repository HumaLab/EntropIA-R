# Snapshot a database to a new file (WAL-aware)

Copies `con` to `dest` using SQLite's `VACUUM INTO`, which produces a
single consistent, self-contained database file. Because the snapshot is
taken by SQLite itself it reads through any live `-wal`/`-shm` sidecars,
so it is safe to run while EntropIA is holding the WAL. The destination
must not already exist.

## Usage

``` r
entropia_copy(con, dest)
```

## Arguments

- con:

  An `entropia_conn` (or any DBI connection).

- dest:

  Destination file path. Must not exist.

## Value

The normalized `dest` path, invisibly.

## Examples

``` r
con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
  package = "entropiaR"
))
dest <- tempfile(fileext = ".sqlite")
entropia_copy(con, dest)
copy_con <- entropia_connect(dest)
entropia_status(copy_con)
#> entropiaR status
#>   path:           /tmp/RtmpDVH1qv/file1ac735b888e8.sqlite
#>   mode:           read-only
#>   schema version: 0029_rag_chunks
#>   valid:          TRUE
#>   row counts:     _migrations=29, sync_meta=8, assets=5, entities=4, app_settings=3 (+26 more)
#>   sync:           last_sync_at 2026-01-15 12:13:20, capture_enabled TRUE
#>   journal:        delete
#>   wal sidecar:    FALSE
entropia_disconnect(copy_con)
entropia_disconnect(con)
```
