# Compare collections (per-collection summary)

**\[experimental\]**

## Usage

``` r
entropia_compare_collections(x, by = "collection_name")
```

## Arguments

- x:

  A data frame or tibble with a collection column.

- by:

  The collection column, selected by name or bare (tidyselect). Default
  `"collection_name"`.

## Value

A tibble with the `by` column, `n_items`/`n_assets` (when `x` carries
those id columns) and `n`, ordered by the collection column.

## Details

Summarises a collected tibble one row per collection. The natural input
is the collected corpus (`dplyr::collect(entropia_corpus(con))`), which
carries `collection_name`, `item_id` and `asset_id`; pass `by` to group
by a different collection column (e.g. `collection_id`).

Each row reports `n` (rows of `x` in that collection) plus `n_items` and
`n_assets` (distinct `item_id` / `asset_id` values, `NA` excluded) when
the input carries those columns. On the collected corpus `n` equals the
number of assets in the collection. Rows are ordered by the collection
column (deterministic).

## Examples

``` r
con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
  package = "entropiaR"
))
corpus <- entropia_collect(entropia_corpus(con))
entropia_compare_collections(corpus)
#> # A tibble: 1 × 4
#>   collection_name   n_items n_assets     n
#>   <chr>               <int>    <int> <int>
#> 1 Archivo de prueba       3        5     5
entropia_disconnect(con)
```
