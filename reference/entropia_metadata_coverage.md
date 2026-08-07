# Metadata coverage (lazy)

Reports which items have no metadata (or an empty one), per grouping.

## Usage

``` r
entropia_metadata_coverage(con, by = "collection")
```

## Arguments

- con:

  A connection returned by
  [`entropia_connect()`](https://github.com/HumaLab/EntropIA-R/reference/entropia_connect.md).

- by:

  Grouping: `"collection"` (default) or `"item"`.

## Value

A `tbl_sql`.

## Details

With `by = "collection"` (default) each row is one collection with
`n_items`, `n_with_metadata`, `n_without_metadata` and `coverage`. With
`by = "item"` each row is one item with its collection context and a
`has_metadata` flag (0/1 integer). The result is lazy (`tbl_sql`).

## Examples

``` r
con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
  package = "entropiaR"
))
entropia_collect(entropia_metadata_coverage(con))
#> # A tibble: 1 × 6
#>   collection_id       collection_name n_items n_with_metadata n_without_metadata
#>   <chr>               <chr>             <int>           <int>              <int>
#> 1 11111111-1111-4111… Archivo de pru…       3               2                  1
#> # ℹ 1 more variable: coverage <dbl>
entropia_disconnect(con)
```
