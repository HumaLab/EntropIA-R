# RAG conversations (lazy)

A lazy [`dplyr::tbl()`](https://dplyr.tidyverse.org/reference/tbl.html)
over the `rag_conversations` table: one row per retrieval-augmented chat
session.

## Usage

``` r
entropia_rag_conversations(con)
```

## Arguments

- con:

  A connection returned by
  [`entropia_connect()`](https://github.com/HumaLab/EntropIA-R/reference/entropia_connect.md).

## Value

A `tbl_sql` on `rag_conversations`.

## Examples

``` r
con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
  package = "entropiaR"
))
entropia_collect(entropia_rag_conversations(con))
#> # A tibble: 1 × 4
#>   id                               title created_at          updated_at         
#>   <chr>                            <chr> <dttm>              <dttm>             
#> 1 bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbb… Cons… 2026-01-15 12:12:00 2026-01-15 12:12:40
entropia_disconnect(con)
```
