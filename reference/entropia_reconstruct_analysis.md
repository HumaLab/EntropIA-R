# Reconstruct LLM analyses against their targets

Joins `llm_results` rows back to the row they analysed. The target table
is named per row by `target_type` (`asset`, `item` or `collection`;
`unknown` and missing targets have no resolvable row), so this cannot be
one SQL join: each row's target is looked up in the table its type names
and returned as a `target` list-column (a one-row tibble, or `NULL` when
unresolvable). The `result` JSON is parsed into a list-column and
timestamps become `POSIXct`.

## Usage

``` r
entropia_reconstruct_analysis(con, target = NULL, job_type = NULL)
```

## Arguments

- con:

  A connection returned by
  [`entropia_connect()`](https://humalab.github.io/EntropIA-R/reference/entropia_connect.md).

- target:

  Optional single target id (an asset/item/collection id) to keep.
  `NULL` (the default) keeps all targets.

- job_type:

  Optional character vector of job types to keep. `NULL` (the default)
  keeps all.

## Value

A tibble of class `entropia_reconstruction`.

## Details

Materialised (one row per `llm_results` row) and ordered
deterministically by `id`; the result carries the
`entropia_reconstruction` class.

## Examples

``` r
con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
  package = "entropiaR"
))
entropia_reconstruct_analysis(con)
#> Reconstructed LLM analyses: 1 row(s)
#>   item       1
#> 
#> # A tibble: 1 × 7
#>   id    target_id target_type job_type result       created_at          target  
#>   <chr> <chr>     <chr>       <chr>    <list>       <dttm>              <list>  
#> 1 llr-… 22222222… item        summary  <named list> 2026-01-15 12:11:40 <tibble>
entropia_disconnect(con)
```
