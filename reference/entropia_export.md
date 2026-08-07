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
  chunk_size = 1000L
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

## Value

The normalized `path`, invisibly.

## Details

Lazy queries are exported in a deterministic row order: when the
rendered SQL carries no `ORDER BY`, the export arranges by the first
column before streaming. Queries with an explicit ordering (e.g.
[`entropia_search()`](https://humalab.github.io/EntropIA-R/reference/entropia_search.md)'s
rank order, or
[`dplyr::arrange()`](https://dplyr.tidyverse.org/reference/arrange.html)
applied first) are exported in that order. Materialised data is written
in the order it was given.

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
