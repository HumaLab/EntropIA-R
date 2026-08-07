# Entity relations (triples with item and collection context)

A lazy [`dplyr::tbl()`](https://dplyr.tidyverse.org/reference/tbl.html)
over `triples` joined to the item and collection it came from, so every
subject/predicate/object extraction carries its provenance:

## Usage

``` r
entropia_entity_relations(con, min_confidence = NULL)
```

## Arguments

- con:

  A connection returned by
  [`entropia_connect()`](https://humalab.github.io/EntropIA-R/reference/entropia_connect.md).

- min_confidence:

  Unused in the current schema (triples carry no confidence column);
  must be `NULL` (the default).

## Value

A `tbl_sql`.

## Details

- `id`, `subject`, `predicate`, `object`: the triple itself.

- `item_id`, `item_title`: the owning item and its title.

- `collection_id`, `collection_name`: the item's collection.

- `asset_id`: the specific asset the triple is scoped to, `NA` for
  item-level triples.

Everything stays lazy: the joins run in SQLite when the result is
collected.

`min_confidence` is accepted for API stability with the plan's research
layer, but the current schema's `triples` table has no confidence
column, so passing a non-`NULL` value errors with guidance rather than
silently doing nothing.

## Examples

``` r
con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
  package = "entropiaR"
))
entropia_collect(entropia_entity_relations(con))
#> # A tibble: 1 × 9
#>   id          subject predicate object item_id asset_id item_title collection_id
#>   <chr>       <chr>   <chr>     <chr>  <chr>   <chr>    <chr>      <chr>        
#> 1 88888888-8… Juan P… particip… la hu… 222222… NA       Manifiest… 11111111-111…
#> # ℹ 1 more variable: collection_name <chr>
entropia_disconnect(con)
```
