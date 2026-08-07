# Schema compatibility status of an EntropIA database

Classifies a database against the shipped column contract
(`inst/schemas/manifest.json`). The status is one of:

## Usage

``` r
entropia_schema_compat(con)
```

## Arguments

- con:

  A connection returned by
  [`entropia_connect()`](https://github.com/HumaLab/EntropIA-R/reference/entropia_connect.md).

## Value

A list of class `entropia_schema_compat` with elements `status`,
`version`, `manifest_head`, `gaps` (the full expected-but-absent column
table), `required_missing`, `optional_missing` and `compatible`.

## Details

- `"known"`: the schema version matches the manifest head
  (`0029_rag_chunks`).

- `"newer"`: the database version is lexicographically ahead of the
  manifest head – a future EntropIA wrote it.

- `"older"`: the database version predates the manifest head.

- `"unknown"`: no `_migrations` table (or an empty one); version
  undetectable.

The required-column check uses the manifest contract: columns tagged
`required = TRUE` whose `min_version` is already reached by the database
version must exist in the live schema. Missing ones are listed in
`required_missing` and make the database incompatible.

## Examples

``` r
con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
  package = "entropiaR"
))
entropia_schema_compat(con)
#> $status
#> [1] "known"
#> 
#> $version
#> [1] "0029_rag_chunks"
#> 
#> $manifest_head
#> [1] "0029_rag_chunks"
#> 
#> $gaps
#> # A tibble: 0 × 7
#> # ℹ 7 variables: table <chr>, column <chr>, type <chr>, required <lgl>,
#> #   min_version <chr>, current_version <chr>, expected <lgl>
#> 
#> $required_missing
#> # A tibble: 0 × 7
#> # ℹ 7 variables: table <chr>, column <chr>, type <chr>, required <lgl>,
#> #   min_version <chr>, current_version <chr>, expected <lgl>
#> 
#> $optional_missing
#> # A tibble: 0 × 7
#> # ℹ 7 variables: table <chr>, column <chr>, type <chr>, required <lgl>,
#> #   min_version <chr>, current_version <chr>, expected <lgl>
#> 
#> $compatible
#> [1] TRUE
#> 
#> attr(,"class")
#> [1] "entropia_schema_compat"
entropia_disconnect(con)
```
