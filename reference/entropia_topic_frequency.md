# Topic frequency (items per topic)

**\[experimental\]**

## Usage

``` r
entropia_topic_frequency(x, by = NULL)
```

## Arguments

- x:

  A data frame or tibble with a `name` column holding topic names.

- by:

  Optional column(s) to break the counts by, selected by name or bare
  (tidyselect). `NULL` (default) produces one row per topic.

## Value

A tibble with the `by` columns (when given), `name` and `n` (item
count), ordered by `n` descending then `name`.

## Details

Counts rows per topic from a collected tibble carrying a topic `name`
column. The natural input is `item_topics` joined to `topics` (e.g.
`dplyr::left_join(entropia_collect(entropia_item_topics(con)), entropia_collect(entropia_topics(con)), by = c("topic_id" = "id"))`).
Because `item_topics` has a `UNIQUE(item_id, topic_id)` constraint,
counting rows per topic counts items per topic. The result is ordered by
descending count then topic name (deterministic).

## Examples

``` r
con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
  package = "entropiaR"
))
item_topics <- entropia_collect(entropia_item_topics(con))
topics <- entropia_collect(entropia_topics(con))
joined <- dplyr::left_join(item_topics, topics, by = c("topic_id" = "id"))
entropia_topic_frequency(joined)
#> # A tibble: 2 × 2
#>   name          n
#>   <chr>     <int>
#> 1 HUELGA        1
#> 2 SINDICATO     1
entropia_disconnect(con)
```
