# Extractions (lazy)

A lazy [`dplyr::tbl()`](https://dplyr.tidyverse.org/reference/tbl.html)
over the `extractions` table. Each row is the OCR text layer of one
asset; `id` is deterministic (`ext-{asset_id}`) and `asset_id` is
UNIQUE, so the table joins 1:1 to
[`entropia_assets()`](https://github.com/HumaLab/EntropIA-R/reference/entropia_assets.md).
`text_content` may embed PDF page markers (`![](page=n,bbox=...)`) which
the text layer
([`entropia_text()`](https://github.com/HumaLab/EntropIA-R/reference/entropia_text.md))
can strip.

## Usage

``` r
entropia_extractions(con)
```

## Arguments

- con:

  A connection returned by
  [`entropia_connect()`](https://github.com/HumaLab/EntropIA-R/reference/entropia_connect.md).

## Value

A `tbl_sql` on `extractions`.

## Examples

``` r
con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
  package = "entropiaR"
))
entropia_collect(entropia_extractions(con))
#> # A tibble: 2 × 6
#>   id                 asset_id text_content method confidence created_at         
#>   <chr>              <chr>    <chr>        <chr>       <dbl> <dttm>             
#> 1 ext-33333333-3333… 3333333… ![](page=1,… ocr          0.91 2026-01-15 12:08:00
#> 2 ext-33333333-3333… 3333333… Segunda pag… pdf_p…       0.88 2026-01-15 12:08:10
entropia_disconnect(con)
```
