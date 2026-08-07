# Collections (lazy)

A lazy [`dplyr::tbl()`](https://dplyr.tidyverse.org/reference/tbl.html)
over the `collections` table. Nothing is fetched at access time:
[`dplyr::filter()`](https://dplyr.tidyverse.org/reference/filter.html),
[`dplyr::select()`](https://dplyr.tidyverse.org/reference/select.html),
[`dplyr::summarise()`](https://dplyr.tidyverse.org/reference/summarise.html)
and friends are translated to SQL and run in SQLite when the result is
collected.

## Usage

``` r
entropia_collections(con)
```

## Arguments

- con:

  A connection returned by
  [`entropia_connect()`](https://github.com/HumaLab/EntropIA-R/reference/entropia_connect.md).

## Value

A `tbl_sql` on `collections`.

## Examples

``` r
con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
  package = "entropiaR"
))
entropia_collections(con) # lazy; nothing fetched until collected
#> # A query:  ?? x 5
#> # Database: sqlite 3.53.3 [/home/runner/work/_temp/Library/entropiaR/extdata/entropia-example.sqlite]
#>   id                                   name    description created_at updated_at
#>   <chr>                                <chr>   <chr>          <int64>    <int64>
#> 1 11111111-1111-4111-8111-111111111111 Archiv… Colección …      1.e12      1.e12
entropia_collect(entropia_collections(con))
#> # A tibble: 1 × 5
#>   id                   name  description created_at          updated_at         
#>   <chr>                <chr> <chr>       <dttm>              <dttm>             
#> 1 11111111-1111-4111-… Arch… Colección … 2026-01-15 12:00:00 2026-01-15 13:00:00
entropia_disconnect(con)
```
