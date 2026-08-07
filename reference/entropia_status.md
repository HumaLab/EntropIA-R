# Compact status summary of an EntropIA database

Read-only snapshot of a connection: path, mode, schema version, row
counts for every readable table (descending), sync freshness from
`sync_meta`, and WAL state (journal mode + sidecar files). Unlike
[`entropia_validate()`](https://github.com/HumaLab/EntropIA-R/reference/entropia_validate.md),
`status()` never reports findings – it describes the database.

## Usage

``` r
entropia_status(con)
```

## Arguments

- con:

  A connection returned by
  [`entropia_connect()`](https://github.com/HumaLab/EntropIA-R/reference/entropia_connect.md).

## Value

A `entropia_status` list with elements `path`, `mode`, `schema_version`,
`row_counts`, `sync`, `wal` and `valid`.

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
