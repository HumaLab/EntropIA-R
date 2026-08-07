# Tables, columns and typed contract of an EntropIA database

Merges the live schema (from `PRAGMA table_xinfo`) with the shipped
column contract (`inst/schemas/manifest.json`). Every readable table
gets one row per column. `source` records whether the row came from the
manifest contract (`"manifest"`) or only exists in the live database
(`"schema"`); columns present in both are reported under the manifest
(the contract is the typed surface). `min_version` is the migration that
guarantees the column, and `required` marks columns whose absence is a
compatibility failure once the database reaches that version.

## Usage

``` r
entropia_schema_info(con)
```

## Arguments

- con:

  A connection returned by
  [`entropia_connect()`](https://humalab.github.io/EntropIA-R/reference/entropia_connect.md).

## Value

A tibble with columns `table`, `column`, `type`, `required`, `contract`,
`min_version` and `source`.

## Examples

``` r
con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
  package = "entropiaR"
))
entropia_schema_info(con)
#> # A tibble: 190 × 7
#>    table       column     type    required contract   min_version      source  
#>    <chr>       <chr>      <chr>   <lgl>    <chr>      <chr>            <chr>   
#>  1 _migrations id         INTEGER TRUE     NA         0001_initial     manifest
#>  2 _migrations name       TEXT    TRUE     NA         0001_initial     manifest
#>  3 _migrations applied_at INTEGER TRUE     datetime_s 0001_initial     manifest
#>  4 annotations id         TEXT    TRUE     NA         0007_annotations manifest
#>  5 annotations asset_id   TEXT    TRUE     NA         0007_annotations manifest
#>  6 annotations page       INTEGER TRUE     int        0007_annotations manifest
#>  7 annotations kind       TEXT    TRUE     enum       0007_annotations manifest
#>  8 annotations color      TEXT    TRUE     NA         0007_annotations manifest
#>  9 annotations x          REAL    TRUE     dbl        0007_annotations manifest
#> 10 annotations y          REAL    TRUE     dbl        0007_annotations manifest
#> # ℹ 180 more rows
entropia_disconnect(con)
```
