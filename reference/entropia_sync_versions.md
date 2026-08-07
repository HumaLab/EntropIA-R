# Sync row versions (lazy)

A lazy [`dplyr::tbl()`](https://dplyr.tidyverse.org/reference/tbl.html)
over `sync_row_versions`, which maps every synced row
`(table_name, row_id)` to the server sequence number it was last seen
at. The result is uncollected, so filtering, joining and aggregating
happen in SQLite; call
[`entropia_collect()`](https://github.com/HumaLab/EntropIA-R/reference/entropia_collect.md)
(or
[`dplyr::collect()`](https://dplyr.tidyverse.org/reference/compute.html))
to bring rows into R.

## Usage

``` r
entropia_sync_versions(con)
```

## Arguments

- con:

  A connection returned by
  [`entropia_connect()`](https://github.com/HumaLab/EntropIA-R/reference/entropia_connect.md).

## Value

A `tbl_sql` on `sync_row_versions`.

## Examples

``` r
con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
  package = "entropiaR"
))
entropia_collect(entropia_sync_versions(con))
#> # A tibble: 2 × 3
#>   table_name  row_id                               server_seq
#>   <chr>       <chr>                                     <int>
#> 1 items       22222222-2222-4222-8222-222222222221         10
#> 2 collections 11111111-1111-4111-8111-111111111111          5
entropia_disconnect(con)
```
