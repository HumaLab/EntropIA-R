# RAG messages (lazy)

A lazy [`dplyr::tbl()`](https://dplyr.tidyverse.org/reference/tbl.html)
over the `rag_messages` table: the ordered messages of a conversation.
`role` is `user` or `assistant`; `sort_index` gives the order within a
conversation. The `sources` column is JSON-in-TEXT (an array of
`{chunk_id, text, score}` citations on assistant messages), parsed by
[`entropia_collect()`](https://humalab.github.io/EntropIA-R/reference/entropia_collect.md)
into a list-column.

## Usage

``` r
entropia_rag_messages(con)
```

## Arguments

- con:

  A connection returned by
  [`entropia_connect()`](https://humalab.github.io/EntropIA-R/reference/entropia_connect.md).

## Value

A `tbl_sql` on `rag_messages`.

## Examples

``` r
con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
  package = "entropiaR"
))
entropia_collect(entropia_rag_messages(con)) # sources -> list-column
#> # A tibble: 2 × 8
#>   id                      conversation_id sort_index role  content sources model
#>   <chr>                   <chr>                <int> <chr> <chr>   <list>  <chr>
#> 1 bbbbbbbb-bbbb-4bbb-8bb… bbbbbbbb-bbbb-…          0 user  ¿Que p… <chr>   NA   
#> 2 bbbbbbbb-bbbb-4bbb-8bb… bbbbbbbb-bbbb-…          1 assi… Hubo u… <df>    entr…
#> # ℹ 1 more variable: created_at <dttm>
entropia_disconnect(con)
```
