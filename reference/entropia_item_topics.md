# Item-topic links (lazy)

A lazy [`dplyr::tbl()`](https://dplyr.tidyverse.org/reference/tbl.html)
over the `item_topics` join table, linking items to topics (one row per
`(item_id, topic_id)` pair, UNIQUE in the app schema).

## Usage

``` r
entropia_item_topics(con)
```

## Arguments

- con:

  A connection returned by
  [`entropia_connect()`](https://humalab.github.io/EntropIA-R/reference/entropia_connect.md).

## Value

A `tbl_sql` on `item_topics`.

## Examples

``` r
con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
  package = "entropiaR"
))
entropia_collect(entropia_item_topics(con))
#> # A tibble: 2 × 4
#>   id                                   item_id      topic_id created_at         
#>   <chr>                                <chr>        <chr>    <dttm>             
#> 1 aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1 22222222-22… 9999999… 2026-01-15 12:11:10
#> 2 aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2 22222222-22… 9999999… 2026-01-15 12:11:20
entropia_disconnect(con)
```
