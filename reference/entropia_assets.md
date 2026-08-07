# Assets (lazy)

A lazy [`dplyr::tbl()`](https://dplyr.tidyverse.org/reference/tbl.html)
over the `assets` table. When the schema has them (migration 0024) the
PDF page columns `parent_asset_id` and `page_number` are exposed so
pages can be joined back to their parent PDF; on older databases the
columns are simply absent. No BLOB column is ever selected: `assets`
carries none, and the accessor never pulls one even if a future schema
adds it.

## Usage

``` r
entropia_assets(con)
```

## Arguments

- con:

  A connection returned by
  [`entropia_connect()`](https://github.com/HumaLab/EntropIA-R/reference/entropia_connect.md).

## Value

A `tbl_sql` on `assets`.

## Examples

``` r
con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
  package = "entropiaR"
))
entropia_assets(con)
#> # A query:  ?? x 9
#> # Database: sqlite 3.53.3 [/home/runner/work/_temp/Library/entropiaR/extdata/entropia-example.sqlite]
#>   id             item_id path  type   size created_at sort_index parent_asset_id
#>   <chr>          <chr>   <chr> <chr> <int>    <int64>      <int> <chr>          
#> 1 33333333-3333… 222222… stor… pdf   20480      1.e12          0 NA             
#> 2 33333333-3333… 222222… stor… pdf   10240      1.e12          1 33333333-3333-…
#> 3 33333333-3333… 222222… stor… pdf   10240      1.e12          2 33333333-3333-…
#> 4 33333333-3333… 222222… stor… image  5120      1.e12          0 NA             
#> 5 33333333-3333… 222222… stor… audio 40960      1.e12          0 NA             
#> # ℹ 1 more variable: page_number <int>
entropia_collect(entropia_assets(con))
#> # A tibble: 5 × 9
#>   id    item_id path  type   size created_at          sort_index parent_asset_id
#>   <chr> <chr>   <chr> <chr> <int> <dttm>                   <int> <chr>          
#> 1 3333… 222222… stor… pdf   20480 2026-01-15 12:07:00          0 NA             
#> 2 3333… 222222… stor… pdf   10240 2026-01-15 12:07:10          1 33333333-3333-…
#> 3 3333… 222222… stor… pdf   10240 2026-01-15 12:07:20          2 33333333-3333-…
#> 4 3333… 222222… stor… image  5120 2026-01-15 12:07:30          0 NA             
#> 5 3333… 222222… stor… audio 40960 2026-01-15 12:07:40          0 NA             
#> # ℹ 1 more variable: page_number <int>
entropia_disconnect(con)
```
