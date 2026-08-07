# Annotations (lazy)

A lazy [`dplyr::tbl()`](https://dplyr.tidyverse.org/reference/tbl.html)
over the `annotations` table (drawing/OCR-cleanup marks on a PDF page).
`kind` is an enum (`rectangle`, `underline`, `crop`, `erase`,
`rotation`); `page` is 1-based and `x`/`y`/`width`/`height` are
coordinates in page units.

## Usage

``` r
entropia_annotations(con)
```

## Arguments

- con:

  A connection returned by
  [`entropia_connect()`](https://github.com/HumaLab/EntropIA-R/reference/entropia_connect.md).

## Value

A `tbl_sql` on `annotations`.

## Examples

``` r
con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
  package = "entropiaR"
))
entropia_collect(entropia_annotations(con))
#> # A tibble: 1 × 11
#>   id     asset_id  page kind  color     x     y width height created_at         
#>   <chr>  <chr>    <int> <chr> <chr> <dbl> <dbl> <dbl>  <dbl> <dttm>             
#> 1 66666… 3333333…     1 rect… #ff0…    10    10   200     50 2026-01-15 12:09:00
#> # ℹ 1 more variable: updated_at <dttm>
entropia_disconnect(con)
```
