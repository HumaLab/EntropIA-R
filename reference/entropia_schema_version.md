# Schema version of an EntropIA database

Returns the authoritative schema version: the lexicographic maximum of
the `_migrations` table (e.g. `"0029_rag_chunks"`). `NA_character_` when
the database has no `_migrations` table.

## Usage

``` r
entropia_schema_version(con)
```

## Arguments

- con:

  A connection returned by
  [`entropia_connect()`](https://github.com/HumaLab/EntropIA-R/reference/entropia_connect.md).

## Value

A single string, or `NA_character_`.

## Examples

``` r
con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
  package = "entropiaR"
))
entropia_schema_version(con)
#> [1] "0029_rag_chunks"
entropia_disconnect(con)
```
