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
`min_version`, `source`, `presence` (logical) and `live_type`. Absent
manifest tables and columns have `presence = FALSE` and missing
`live_type`; `type` retains the manifest declaration where available.

## Examples

``` r
con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
  package = "entropiaR"
))
entropia_schema_info(con)
#> # A tibble: 190 × 9
#>    table    column type  required contract min_version source presence live_type
#>    <chr>    <chr>  <chr> <lgl>    <chr>    <chr>       <chr>  <lgl>    <chr>    
#>  1 _migrat… id     INTE… TRUE     NA       0001_initi… manif… TRUE     INTEGER  
#>  2 _migrat… name   TEXT  TRUE     NA       0001_initi… manif… TRUE     TEXT     
#>  3 _migrat… appli… INTE… TRUE     datetim… 0001_initi… manif… TRUE     INTEGER  
#>  4 annotat… id     TEXT  TRUE     NA       0007_annot… manif… TRUE     TEXT     
#>  5 annotat… asset… TEXT  TRUE     NA       0007_annot… manif… TRUE     TEXT     
#>  6 annotat… page   INTE… TRUE     int      0007_annot… manif… TRUE     INTEGER  
#>  7 annotat… kind   TEXT  TRUE     enum     0007_annot… manif… TRUE     TEXT     
#>  8 annotat… color  TEXT  TRUE     NA       0007_annot… manif… TRUE     TEXT     
#>  9 annotat… x      REAL  TRUE     dbl      0007_annot… manif… TRUE     REAL     
#> 10 annotat… y      REAL  TRUE     dbl      0007_annot… manif… TRUE     REAL     
#> # ℹ 180 more rows
entropia_disconnect(con)
```
