# Read the provenance stamp of a reproducible dataset

Returns the `entropia_prov` attribute attached by
[`entropia_analysis_dataset()`](https://humalab.github.io/EntropIA-R/reference/entropia_analysis_dataset.md):
a list recording the dataset `name`, the database `schema_version`, the
`schema_hash`, the `source_path`, the captured `filters`, the
`package_version`, the `built_at` timestamp and the `r_version`. Aborts
with `entropia_error_invalid_argument` when `x` carries no provenance
stamp. The current data digest is recomputed. Changed values, classes,
columns or row order yield `scope = "derived"` and `query = NULL`;
`origin` retains the original digest, SQL and selection recipe. Origin
SQL is not represented as a recipe for transformed rows.

## Usage

``` r
entropia_provenance(x)
```

## Arguments

- x:

  An object carrying a provenance stamp, e.g. the output of
  [`entropia_analysis_dataset()`](https://humalab.github.io/EntropIA-R/reference/entropia_analysis_dataset.md).

## Value

A list of class `entropia_provenance`.

## Examples

``` r
con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
  package = "entropiaR"
))
ds <- entropia_analysis_dataset(con, asset_type == "image")
entropia_provenance(ds)
#> entropiaR dataset provenance
#>   name:           <unnamed>
#>   schema version: 0029_rag_chunks
#>   schema hash:    09d4c603b66d68c4c0cef0f51ff09a04fb30a49fe200907ef69693d11dd25732
#>   dataset hash:   49711da64be7bf040081faaefaf105c6c37b0b1657f20c8d54af5731f498bd8b
#>   scope:          origin
#>   source path:    /home/runner/work/_temp/Library/entropiaR/extdata/entropia-example.sqlite
#>   filters:        asset_type == "image"
#>   package:        0.0.0.9000
#>   built at:       2026-09-11T18:07:06.765Z
#>   R version:      R version 4.6.1 (2026-06-24)
entropia_disconnect(con)
```
