# Notes (lazy)

A lazy [`dplyr::tbl()`](https://dplyr.tidyverse.org/reference/tbl.html)
over the `notes` table. Notes are item-level by default; when `asset_id`
is present (migration 0014) the note is scoped to a specific asset
instead. `asset_id` is NULL for item-level notes.

## Usage

``` r
entropia_notes(con)
```

## Arguments

- con:

  A connection returned by
  [`entropia_connect()`](https://github.com/HumaLab/EntropIA-R/reference/entropia_connect.md).

## Value

A `tbl_sql` on `notes`.

## Examples

``` r
con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
  package = "entropiaR"
))
entropia_collect(entropia_notes(con))
#> # A tibble: 2 × 6
#>   id            item_id content created_at          updated_at          asset_id
#>   <chr>         <chr>   <chr>   <dttm>              <dttm>              <chr>   
#> 1 55555555-555… 222222… Nota a… 2026-01-15 12:08:40 2026-01-15 12:08:40 NA      
#> 2 55555555-555… 222222… Nota s… 2026-01-15 12:08:50 2026-01-15 12:08:50 3333333…
entropia_disconnect(con)
```
