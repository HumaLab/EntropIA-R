# Topics (lazy)

A lazy [`dplyr::tbl()`](https://dplyr.tidyverse.org/reference/tbl.html)
over the `topics` table. Topic names are normalised to UPPERCASE by the
app (UNIQUE constraint); the accessor returns them exactly as stored and
never re-normalises.

## Usage

``` r
entropia_topics(con)
```

## Arguments

- con:

  A connection returned by
  [`entropia_connect()`](https://github.com/HumaLab/EntropIA-R/reference/entropia_connect.md).

## Value

A `tbl_sql` on `topics`.

## Examples

``` r
con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
  package = "entropiaR"
))
entropia_collect(entropia_topics(con))
#> # A tibble: 2 × 3
#>   id                                   name      created_at         
#>   <chr>                                <chr>     <dttm>             
#> 1 99999999-9999-4999-8999-999999999991 HUELGA    2026-01-15 12:10:50
#> 2 99999999-9999-4999-8999-999999999992 SINDICATO 2026-01-15 12:11:00
entropia_disconnect(con)
```
