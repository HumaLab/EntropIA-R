# Sync conflicts (lazy)

A lazy [`dplyr::tbl()`](https://dplyr.tidyverse.org/reference/tbl.html)
over `sync_conflicts`. Each row records one conflict the sync engine
could not resolve automatically. `reason` is a documented enum:
`lww_lost` (lost the last-writer-wins race), `parent_deleted`,
`unique_collision`, `apply_error`, `schema_drift`, `blob_missing`,
`blob_hash_mismatch`. `created_at` is epoch milliseconds;
`loser_payload` and `winner_summary` are JSON text.

## Usage

``` r
entropia_conflicts(con)
```

## Arguments

- con:

  A connection returned by
  [`entropia_connect()`](https://github.com/HumaLab/EntropIA-R/reference/entropia_connect.md).

## Value

A `tbl_sql` on `sync_conflicts`.

## Examples

``` r
con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
  package = "entropiaR"
))
entropia_collect(entropia_conflicts(con))
#> # A tibble: 1 × 8
#>   id     table_name row_id                   reason loser_payload winner_summary
#>   <chr>  <chr>      <chr>                    <chr>  <chr>         <chr>         
#> 1 conf-1 items      22222222-2222-4222-8222… lww_l… {}            {}            
#> # ℹ 2 more variables: created_at <dttm>, acknowledged <int>
entropia_disconnect(con)
```
