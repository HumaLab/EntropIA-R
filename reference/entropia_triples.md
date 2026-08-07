# Triples (lazy)

A lazy [`dplyr::tbl()`](https://dplyr.tidyverse.org/reference/tbl.html)
over the `triples` table (subject/predicate/object extractions).
`created_at` uses the magnitude-guarded `datetime_auto` contract;
`asset_id` is NULL for item-level triples.

## Usage

``` r
entropia_triples(con)
```

## Arguments

- con:

  A connection returned by
  [`entropia_connect()`](https://github.com/HumaLab/EntropIA-R/reference/entropia_connect.md).

## Value

A `tbl_sql` on `triples`.

## Examples

``` r
con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
  package = "entropiaR"
))
entropia_collect(entropia_triples(con))
#> # A tibble: 1 × 7
#>   id               item_id subject predicate object created_at          asset_id
#>   <chr>            <chr>   <chr>   <chr>     <chr>  <dttm>              <chr>   
#> 1 88888888-8888-4… 222222… Juan P… particip… la hu… 2026-01-15 12:10:40 NA      
entropia_disconnect(con)
```
