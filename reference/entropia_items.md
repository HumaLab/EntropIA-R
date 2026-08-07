# Items (lazy)

A lazy [`dplyr::tbl()`](https://dplyr.tidyverse.org/reference/tbl.html)
over the `items` table. The `search_text` generated column is included
(it is cheap – stored, not computed on read). JSON in `metadata` stays
raw text until
[`entropia_collect()`](https://humalab.github.io/EntropIA-R/reference/entropia_collect.md)
applies the column contract.

## Usage

``` r
entropia_items(con)
```

## Arguments

- con:

  A connection returned by
  [`entropia_connect()`](https://humalab.github.io/EntropIA-R/reference/entropia_connect.md).

## Value

A `tbl_sql` on `items`.

## Examples

``` r
con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
  package = "entropiaR"
))
entropia_items(con)
#> # A query:  ?? x 7
#> # Database: sqlite 3.53.3 [/home/runner/work/_temp/Library/entropiaR/extdata/entropia-example.sqlite]
#>   id              title collection_id metadata created_at updated_at search_text
#>   <chr>           <chr> <chr>         <chr>       <int64>    <int64> <chr>      
#> 1 22222222-2222-… Mani… 11111111-111… "{\"__e…      1.e12      1.e12 "Manifiest…
#> 2 22222222-2222-… Cart… 11111111-111… "{\"__e…      1.e12      1.e12 "Carta al …
#> 3 22222222-2222-… Foto… 11111111-111…  NA           1.e12      1.e12 "Fotografí…
entropia_collect(entropia_items(con)) # metadata -> list-column, created_at -> POSIXct
#> # A tibble: 3 × 7
#>   id    title collection_id metadata     created_at          updated_at         
#>   <chr> <chr> <chr>         <list>       <dttm>              <dttm>             
#> 1 2222… Mani… 11111111-111… <named list> 2026-01-15 12:01:00 2026-01-15 12:02:00
#> 2 2222… Cart… 11111111-111… <named list> 2026-01-15 12:03:00 2026-01-15 12:04:00
#> 3 2222… Foto… 11111111-111… <chr [1]>    2026-01-15 12:05:00 2026-01-15 12:06:00
#> # ℹ 1 more variable: search_text <chr>
entropia_disconnect(con)
```
