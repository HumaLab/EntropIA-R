# OCR coverage (lazy)

Reports which assets are missing an OCR extraction, or whose extraction
text is empty/whitespace-only, per grouping. Everything stays lazy: the
result is a `tbl_sql` whose joins and aggregations run in SQLite when
collected.

## Usage

``` r
entropia_ocr_coverage(con, by = "collection")
```

## Arguments

- con:

  A connection returned by
  [`entropia_connect()`](https://github.com/HumaLab/EntropIA-R/reference/entropia_connect.md).

- by:

  Grouping: `"collection"` (default), `"item"`, or `"asset"`.

## Value

A `tbl_sql`.

## Details

With `by = "asset"` (per-asset detail) each row is one asset with its
item/collection context and two flags:

- `has_extraction`: the asset has an extraction row.

- `text_empty`: the extraction text is empty/whitespace-only (`NA` when
  the asset has no extraction).

The flags are 0/1 integers (SQLite booleans); filter with `== 1`/`== 0`.
With `by = "item"` or `by = "collection"` the result is a grouped
summary with `n_assets`, `n_with_extraction`, `n_missing` (no extraction
row), `n_empty` (extraction present but empty) and `coverage` (fraction
of assets with a non-empty extraction).

## Examples

``` r
con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
  package = "entropiaR"
))
entropia_collect(entropia_ocr_coverage(con))
#> # A tibble: 1 × 7
#>   collection_id     collection_name n_assets n_with_extraction n_empty n_missing
#>   <chr>             <chr>              <int>             <int>   <int>     <int>
#> 1 11111111-1111-41… Archivo de pru…        5                 2       0         3
#> # ℹ 1 more variable: coverage <dbl>
entropia_collect(entropia_ocr_coverage(con, by = "asset"))
#> # A tibble: 5 × 7
#>   asset_id       item_id asset_type collection_id collection_name has_extraction
#>   <chr>          <chr>   <chr>      <chr>         <chr>                    <int>
#> 1 33333333-3333… 222222… pdf        11111111-111… Archivo de pru…              1
#> 2 33333333-3333… 222222… pdf        11111111-111… Archivo de pru…              1
#> 3 33333333-3333… 222222… pdf        11111111-111… Archivo de pru…              0
#> 4 33333333-3333… 222222… image      11111111-111… Archivo de pru…              0
#> 5 33333333-3333… 222222… audio      11111111-111… Archivo de pru…              0
#> # ℹ 1 more variable: text_empty <int>
entropia_disconnect(con)
```
