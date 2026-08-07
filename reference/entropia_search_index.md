# Items full-text index (lazy, raw)

A lazy [`dplyr::tbl()`](https://dplyr.tidyverse.org/reference/tbl.html)
over the contentless FTS5 table `fts_items`. This is an advanced, raw
accessor: contentless FTS5 stores no column content, so selecting its
columns directly reads `NULL`. To get searchable text, join to
[`entropia_items()`](https://humalab.github.io/EntropIA-R/reference/entropia_items.md)
on rowid (`items i ON i.rowid = fts_items.rowid`) or use
[`entropia_search()`](https://humalab.github.io/EntropIA-R/reference/entropia_search.md).

## Usage

``` r
entropia_search_index(con)
```

## Arguments

- con:

  A connection returned by
  [`entropia_connect()`](https://humalab.github.io/EntropIA-R/reference/entropia_connect.md).

## Value

A `tbl_sql` on `fts_items`.

## Examples

``` r
con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
  package = "entropiaR"
))
# Raw contentless table: columns read NULL; join to items on rowid for text.
entropia_collect(entropia_search_index(con))
#> # A tibble: 3 × 4
#>   item_id title metadata extracted_text
#>   <lgl>   <lgl> <lgl>    <lgl>         
#> 1 NA      NA    NA       NA            
#> 2 NA      NA    NA       NA            
#> 3 NA      NA    NA       NA            
entropia_disconnect(con)
```
