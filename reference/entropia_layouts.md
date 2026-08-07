# Layouts (lazy)

A lazy [`dplyr::tbl()`](https://dplyr.tidyverse.org/reference/tbl.html)
over the `layouts` table. Each row is the page-layout analysis of one
asset; `id` is deterministic (`lay-{asset_id}`) and `asset_id` is UNIQUE
(1:1 with
[`entropia_assets()`](https://humalab.github.io/EntropIA-R/reference/entropia_assets.md)).
`regions` and `blocks` are JSON-in-TEXT columns, parsed by
[`entropia_collect()`](https://humalab.github.io/EntropIA-R/reference/entropia_collect.md).

## Usage

``` r
entropia_layouts(con)
```

## Arguments

- con:

  A connection returned by
  [`entropia_connect()`](https://humalab.github.io/EntropIA-R/reference/entropia_connect.md).

## Value

A `tbl_sql` on `layouts`.

## Examples

``` r
con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
  package = "entropiaR"
))
entropia_collect(entropia_layouts(con))
#> # A tibble: 1 × 8
#>   id                      asset_id regions blocks model image_width image_height
#>   <chr>                   <chr>    <list>  <list> <chr>       <int>        <int>
#> 1 lay-33333333-3333-4333… 3333333… <df>    <df>   layo…        1000         1400
#> # ℹ 1 more variable: created_at <dttm>
entropia_disconnect(con)
```
