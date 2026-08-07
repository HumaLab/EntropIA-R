# Entity frequency (top entities by type)

**\[experimental\]**

## Usage

``` r
entropia_entity_frequency(x, by = NULL)
```

## Arguments

- x:

  A data frame or tibble of collected entity rows, carrying
  `entity_type` and `value` columns.

- by:

  Optional column(s) to break the counts by, selected by name or bare
  (tidyselect). `NULL` (default) produces one row per `entity_type` x
  `value`.

## Value

A tibble with the `by` columns (when given), `entity_type`, `value` and
`n` (row count), ordered by `entity_type` then `n` descending then
`value`.

## Details

Counts entity occurrences from a collected entities tibble: for every
distinct `entity_type` x `value` pair, the number of rows carrying it.
The result is ordered by `entity_type` then descending count, so the top
entities of each type read off the top of each block. Pass the collected
output of
[`entropia_entities()`](https://github.com/HumaLab/EntropIA-R/reference/entropia_entities.md)
directly, or join it to `items` and `collections` first and pass `by` to
break the counts down further (e.g. by `collection_name`). Soft-deleted
rows are whatever the input carries – use `include_deleted = TRUE` on
[`entropia_entities()`](https://github.com/HumaLab/EntropIA-R/reference/entropia_entities.md)
to count them.

## Examples

``` r
con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
  package = "entropiaR"
))
entities <- entropia_collect(entropia_entities(con))
entropia_entity_frequency(entities)
#> # A tibble: 3 × 3
#>   entity_type  value                     n
#>   <chr>        <chr>                 <int>
#> 1 organization Sindicato Ferroviario     1
#> 2 person       Juan Pérez                1
#> 3 place        Plaza de Mayo             1
entropia_disconnect(con)
```
