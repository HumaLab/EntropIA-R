# Export data to a file

Writes a data frame/tibble (or a lazy query) to a file in one of six
formats. `csv`, `tsv`, `json` and `rds` always work; `parquet` and
`arrow` (Feather v2) require the optional `arrow` package. A lazy
`tbl_sql` input is exported without being collected into memory for the
delimited formats: the query is streamed in bounded chunks via
[`DBI::dbSendQuery`](https://dbi.r-dbi.org/reference/dbSendQuery.html) +
[`DBI::dbFetch`](https://dbi.r-dbi.org/reference/dbFetch.html), so
exporting a large corpus to CSV stays flat in memory. `json`, `rds`,
`parquet` and `arrow` are whole-file formats and collect the query
first.

## Usage

``` r
entropia_export(
  x,
  path,
  format = c("csv", "tsv", "json", "rds", "parquet", "arrow"),
  chunk_size = 1000L,
  order_by = NULL
)
```

## Arguments

- x:

  A data frame/tibble or a lazy `tbl_sql` table (e.g. from
  [`entropia_corpus()`](https://humalab.github.io/EntropIA-R/reference/entropia_corpus.md)
  or
  [`entropia_items()`](https://humalab.github.io/EntropIA-R/reference/entropia_items.md)).

- path:

  Destination file path (a single path; parent directories are not
  created).

- format:

  One of `"csv"`, `"tsv"`, `"json"`, `"rds"`, `"parquet"` or `"arrow"`.

- chunk_size:

  Rows fetched per chunk when streaming a lazy input to a delimited
  format. Default `1000L`.

- order_by:

  Optional character vector of primary ordering columns. All comparable
  output columns are appended as tie-breakers.

## Value

The normalized `path`, invisibly.

## Details

Lazy queries retain ordering recorded in dbplyr's `lazy_query$order_by`,
with all projected columns appended as tie-breakers. SQLite compares
BLOBs bytewise. Ordering hidden inside opaque SQL or unknown query
objects cannot be recovered: supply `order_by` explicitly in that case.
Identical projected rows are interchangeable. Materialised data retains
its input order unless `order_by` is supplied; list columns cannot be
explicit in-memory sort keys. CSV and TSV use one UTF-8 file connection
for the entire export.

The column contract is NOT applied by the export: a lazy query exports
the raw values SQLite stores (epoch timestamps as integers, JSON-in-TEXT
as text). Collect with
[`entropia_collect()`](https://humalab.github.io/EntropIA-R/reference/entropia_collect.md)
first – and pass the result as a tibble – to export typed values
(`POSIXct` timestamps and JSON list-columns).

## Examples

``` r
tmp <- tempfile(fileext = ".csv")
entropia_export(tibble::tibble(id = 1:2, label = c("a", "b")), tmp)
read.csv(tmp)
#>   id label
#> 1  1     a
#> 2  2     b
```
