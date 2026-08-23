# Connecting to an EntropIA database

## Read-only by design

EntropIA stores your corpus in a SQLite database. The `entropiaR`
package is the tidy, typed interface to that database — and in v1 it is
**read-only by construction**.
[`entropia_connect()`](https://humalab.github.io/EntropIA-R/reference/entropia_connect.md)
opens the file with SQLite’s read-only flags and re-asserts
`PRAGMA query_only = ON`, so nothing in this package can ever modify
your database. This is deliberate: the database may be *live* under the
EntropIA desktop app (WAL journal, a sync engine, and 81 triggers guard
the schema), and a read-only client is safe to point at it at any time.

``` r

# Even requesting a write connection fails in v1.
entropia_connect(system.file("extdata", "entropia-example.sqlite", package = "entropiaR"),
  write = TRUE
)
#> Error in `entropia_connect()`:
#> ! Write access is not available in entropiaR v1.
#> ℹ v1 is read-only. Write support ships in v2 -- see
#>   vignettes/administration.Rmd for the design.
```

## Opening a connection

The package ships a small example database so you can follow along
without your own data. Connect to it with
[`entropia_connect()`](https://humalab.github.io/EntropIA-R/reference/entropia_connect.md):

``` r

con <- entropia_connect(system.file("extdata", "entropia-example.sqlite", package = "entropiaR"))
con
#> <SQLiteConnection>
#>   Path: /home/runner/work/_temp/Library/entropiaR/extdata/entropia-example.sqlite
#>   Extensions: TRUE
```

The result is an `entropia_conn`, a specialized DBI connection. It *is*
a real `SQLiteConnection`, so every DBI function keeps working, and it
carries a few extra attributes — the file path, the open mode, the
schema version, and a content hash of the schema:

``` r

class(con)
#> [1] "entropia_conn"
#> attr(,"package")
#> [1] "entropiaR"
summary(con)
#> entropiaR connection summary
#>   path:           /home/runner/work/_temp/Library/entropiaR/extdata/entropia-example.sqlite
#>   mode:           read-only
#>   schema version: 0029_rag_chunks
#>   content hash:   09d4c603b66d68c4c0cef0f51ff09a04fb30a49fe200907ef69693d11dd25732
#>   valid:          TRUE
DBI::dbIsValid(con)
#> [1] TRUE
```

Connect to your own EntropIA database the same way:

``` r

con <- entropia_connect("path/to/entropia.sqlite")
```

The path must be an existing SQLite file. Missing files and non-SQLite
files raise typed, actionable errors:

``` r

entropia_connect("no/such/database.sqlite")
#> Error in `entropia_connect()`:
#> ! Database file not found: no/such/database.sqlite.
#> ℹ Create the database with the EntropIA desktop app first, or pass a different
#>   path.
```

``` r

notsqlite <- tempfile(fileext = ".txt")
writeLines("not a database", notsqlite)
entropia_connect(notsqlite)
#> Error in `entropia_connect()`:
#> ! /tmp/RtmpDegWUE/file2029d5b8e54.txt is not a SQLite database.
#> ℹ entropiaR reads EntropIA SQLite databases. The file does not begin with the
#>   SQLite header.
```

## The schema version

There is no numeric schema version in the EntropIA database — the
authoritative version is the newest row in the `_migrations` table.
`entropiaR` reads it for you:

``` r

entropia_schema_version(con)
#> [1] "0029_rag_chunks"
```

[`entropia_schema_compat()`](https://humalab.github.io/EntropIA-R/reference/entropia_schema_compat.md)
classifies the database against the column contract shipped with the
package (`known`, `newer`, `older`, or `unknown`) and reports any
missing columns:

``` r

compat <- entropia_schema_compat(con)
compat$status
#> [1] "known"
compat$compatible
#> [1] TRUE
```

[`entropia_schema_info()`](https://humalab.github.io/EntropIA-R/reference/entropia_schema_info.md)
lists every readable table with the columns and the type contract the
package will apply on collect:

``` r

schema <- entropia_schema_info(con)
head(schema, 10)
#> # A tibble: 10 × 7
#>    table       column     type    required contract   min_version      source  
#>    <chr>       <chr>      <chr>   <lgl>    <chr>      <chr>            <chr>   
#>  1 _migrations id         INTEGER TRUE     NA         0001_initial     manifest
#>  2 _migrations name       TEXT    TRUE     NA         0001_initial     manifest
#>  3 _migrations applied_at INTEGER TRUE     datetime_s 0001_initial     manifest
#>  4 annotations id         TEXT    TRUE     NA         0007_annotations manifest
#>  5 annotations asset_id   TEXT    TRUE     NA         0007_annotations manifest
#>  6 annotations page       INTEGER TRUE     int        0007_annotations manifest
#>  7 annotations kind       TEXT    TRUE     enum       0007_annotations manifest
#>  8 annotations color      TEXT    TRUE     NA         0007_annotations manifest
#>  9 annotations x          REAL    TRUE     dbl        0007_annotations manifest
#> 10 annotations y          REAL    TRUE     dbl        0007_annotations manifest
```

## A compact status report

[`entropia_status()`](https://humalab.github.io/EntropIA-R/reference/entropia_status.md)
gives you the headline numbers at a glance — path, mode, schema version,
row counts, sync freshness, and WAL state:

``` r

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
```

## Schema compatibility policy

Because EntropIA evolves, `entropiaR` checks the schema on open and
behaves according to `options(entropiaR.schema_policy)`:

- `"warn"` (default) — warns and proceeds, tolerating
  unknown/newer/older schemas as long as the required columns exist;
- `"error"` — hard stop on an unknown (newer) schema;
- `"allow"` — silent, no warnings.

The backward-compatible posture is the default: unknown columns are
ignored, missing optional columns degrade gracefully, and only genuinely
missing *required* columns raise `entropia_error_schema_incompatible`.

``` r

options(entropiaR.schema_policy = "warn") # the default; scoped to this session
```

## Validating the database

[`entropia_validate()`](https://humalab.github.io/EntropIA-R/reference/entropia_validate.md)
runs a structural diagnostic: core tables present, required columns
present, per-table row counts, empty-database detection, and
relationship sanity. It returns a findings tibble — an empty one means a
clean bill of health:

``` r

findings <- entropia_validate(con)
findings
#> # A tibble: 0 × 5
#> # ℹ 5 variables: severity <chr>, kind <chr>, table <chr>, column <chr>,
#> #   message <chr>
```

## Snapshotting for long analyses

If you are about to run something long or heavy, snapshot the database
first with
[`entropia_copy()`](https://humalab.github.io/EntropIA-R/reference/entropia_copy.md).
It uses SQLite’s `VACUUM INTO`, which reads *through* any WAL sidecars
and writes a single self-contained file — a safe, stable working copy:

``` r

copy_path <- tempfile(fileext = ".sqlite")
entropia_copy(con, copy_path)
copy_con <- entropia_connect(copy_path)
entropia_status(copy_con)$row_counts
#>               _migrations                 sync_meta                    assets 
#>                        29                         8                         5 
#>                  entities              app_settings                 fts_items 
#>                         4                         3                         3 
#>                     items               extractions               item_topics 
#>                         3                         2                         2 
#>                     notes              rag_messages         sync_row_versions 
#>                         2                         2                         2 
#>                    topics               annotations               collections 
#>                         2                         1                         1 
#>                   layouts               llm_results rag_asset_embedding_state 
#>                         1                         1                         1 
#>                rag_chunks            rag_chunks_fts         rag_conversations 
#>                         1                         1                         1 
#>            sync_conflicts            transcriptions                   triples 
#>                         1                         1                         1 
#>                vec_assets           sync_blob_index                sync_oplog 
#>                         1                         0                         0 
#>        sync_pending_blobs          sync_pending_fts         sync_pending_rows 
#>                         0                         0                         0 
#>        sync_topic_aliases 
#>                         0
entropia_disconnect(copy_con)
```

## Closing

Close a connection with
[`entropia_disconnect()`](https://humalab.github.io/EntropIA-R/reference/entropia_disconnect.md).
It is idempotent — closing twice is harmless — and after closing,
`dbIsValid()` reports `FALSE`:

``` r

entropia_disconnect(con)
DBI::dbIsValid(con)
#> [1] FALSE
```

That is the whole connection surface. Next, explore the corpus with
[`vignette("corpus")`](https://humalab.github.io/EntropIA-R/articles/corpus.md),
or pull text and metadata with
[`vignette("text")`](https://humalab.github.io/EntropIA-R/articles/text.md).
