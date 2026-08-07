# Validate the structure of an EntropIA database

Reports structural health as a tibble of findings. The check is
read-only and `EXPLAIN`-free: it compares the live schema
(`sqlite_master` + `PRAGMA table_xinfo`) against the shipped column
contract and counts rows.

## Usage

``` r
entropia_validate(con)
```

## Arguments

- con:

  A connection returned by
  [`entropia_connect()`](https://github.com/HumaLab/EntropIA-R/reference/entropia_connect.md).

## Value

A tibble of findings with columns `severity`, `kind`, `table`, `column`
and `message`, plus `row_counts` and `schema_version` attributes.

## Details

Each finding has a `severity` (`"error"`, `"warning"`, `"info"`), a
`kind` (`"table_missing"`, `"column_missing"`, `"empty_database"`,
`"no_migrations"`, or `"unreadable"`), the affected `table`/`column` (or
`NA`), and a plain-text `message`. A healthy database returns an empty
findings tibble: zero error-severity findings and no warnings for a
complete post-0029 schema. Row counts for every readable table and the
detected schema version are attached as the `row_counts` and
`schema_version` attributes.

Unlike the accessors, `validate()` never raises
`entropia_error_table_missing` or `entropia_error_column_missing`:
structural gaps are findings, not errors. The one exception is an
unreadable (corrupt) file, which yields a single `"unreadable"` finding
of severity `"error"`.

## Examples

``` r
con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
  package = "entropiaR"
))
entropia_validate(con) # zero findings on the example database
#> # A tibble: 0 × 5
#> # ℹ 5 variables: severity <chr>, kind <chr>, table <chr>, column <chr>,
#> #   message <chr>
entropia_disconnect(con)
```
