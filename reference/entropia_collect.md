# Collect and apply the column contract

Like
[`dplyr::collect()`](https://dplyr.tidyverse.org/reference/compute.html)
on a lazy table, but additionally applies the package's column contract:
epoch-millisecond timestamps become `POSIXct` (UTC), JSON-in-TEXT
columns (e.g. `transcriptions.segments`) become list-columns, and BLOB
columns stay raw. Columns the manifest does not describe are returned
unchanged.

## Usage

``` r
entropia_collect(x, n = Inf, ...)
```

## Arguments

- x:

  A lazy table, e.g. from
  [`entropia_items()`](https://humalab.github.io/EntropIA-R/reference/entropia_items.md).

- n:

  Maximum number of rows to fetch, passed to
  [`dplyr::collect()`](https://dplyr.tidyverse.org/reference/compute.html).

- ...:

  Additional arguments passed to
  [`dplyr::collect()`](https://dplyr.tidyverse.org/reference/compute.html).

## Value

A
[`tibble::tibble()`](https://tibble.tidyverse.org/reference/tibble.html)
with the column contract applied.

## Details

The contract is resolved from the table's base table. For a lazy query
that is not a simple single-table read (joins, subqueries) the columns
are returned as SQLite produced them – keep filters/selects inside the
lazy query for best results.

## Examples

``` r
con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
  package = "entropiaR"
))
entropia_collect(entropia_items(con)) # created_at -> POSIXct, metadata -> list-column
#> # A tibble: 3 × 7
#>   id    title collection_id metadata     created_at          updated_at         
#>   <chr> <chr> <chr>         <list>       <dttm>              <dttm>             
#> 1 2222… Mani… 11111111-111… <named list> 2026-01-15 12:01:00 2026-01-15 12:02:00
#> 2 2222… Cart… 11111111-111… <named list> 2026-01-15 12:03:00 2026-01-15 12:04:00
#> 3 2222… Foto… 11111111-111… <chr [1]>    2026-01-15 12:05:00 2026-01-15 12:06:00
#> # ℹ 1 more variable: search_text <chr>
entropia_disconnect(con)
```
