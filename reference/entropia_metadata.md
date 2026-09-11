# Item metadata (parsed)

Reads `items.metadata` – JSON-in-TEXT on every item – into tidy rows:
one row per item (in the order returned by the base query) with
`item_id`, the parsed `__entropia_file_metadata` fields `original_name`,
`original_path` and `imported_at` (ISO-8601, as `POSIXct` in UTC), and
one list-column per remaining top-level metadata key. Items without
metadata get one row with `NA` in the parsed fields and `NULL` in the
list-columns.

## Usage

``` r
entropia_metadata(con, items = NULL, parse = TRUE)
```

## Arguments

- con:

  A connection returned by
  [`entropia_connect()`](https://humalab.github.io/EntropIA-R/reference/entropia_connect.md).

- items:

  `NULL` for all items, a character vector of item ids to keep, or a
  lazy table of items (must have `id` and `metadata` columns). Default
  `NULL`.

- parse:

  When `TRUE` (default) parse `metadata` into the tidy field columns;
  when `FALSE` return the raw `metadata` text column.

## Value

A
[`tibble::tibble()`](https://tibble.tidyverse.org/reference/tibble.html)
with one row per item.

## Details

Unlike the lazy accessors this function materialises: parsing JSON to
list-columns is an R-side step. `parse = FALSE` returns the raw
`metadata` text alongside `item_id` instead. Parsed output also retains
`raw_metadata` and an `extra_metadata` list-column containing top-level
keys that collide with output column names. Non-scalar file fields
become typed missing values. The `diagnostics` attribute is a tibble
with `item_id`, `field`, and `problem`, including malformed JSON and
invalid dates.

## Examples

``` r
con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
  package = "entropiaR"
))
entropia_metadata(con)
#> # A tibble: 3 × 7
#>   item_id           original_name original_path imported_at         raw_metadata
#>   <chr>             <chr>         <chr>         <dttm>              <chr>       
#> 1 22222222-2222-42… manifiesto.p… /docs/manifi… 2026-01-15 12:05:00 "{\"__entro…
#> 2 22222222-2222-42… carta.mp3     /docs/carta.… 2026-01-15 12:06:00 "{\"__entro…
#> 3 22222222-2222-42… NA            NA            NA                   NA         
#> # ℹ 2 more variables: extra_metadata <list>, page_count <list>
entropia_metadata(con, parse = FALSE) # raw metadata text
#> # A tibble: 3 × 2
#>   item_id                              metadata                                 
#>   <chr>                                <chr>                                    
#> 1 22222222-2222-4222-8222-222222222221 "{\"__entropia_file_metadata\":{\"origin…
#> 2 22222222-2222-4222-8222-222222222222 "{\"__entropia_file_metadata\":{\"origin…
#> 3 22222222-2222-4222-8222-222222222223  NA                                      
entropia_disconnect(con)
```
