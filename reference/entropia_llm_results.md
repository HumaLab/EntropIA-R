# LLM results (lazy)

A lazy [`dplyr::tbl()`](https://dplyr.tidyverse.org/reference/tbl.html)
over the `llm_results` table: rows produced by LLM jobs (summaries,
analyses, ...) linked to their target via `target_id` plus `target_type`
(`asset`, `item`, `collection` or `unknown`). The `id` is deterministic:
`llr-{target_type}-{target_id}-{job_type}`. The `result` column is
JSON-in-TEXT, parsed by
[`entropia_collect()`](https://humalab.github.io/EntropIA-R/reference/entropia_collect.md)
into a list-column.

## Usage

``` r
entropia_llm_results(con, target_type = NULL, job_type = NULL)
```

## Arguments

- con:

  A connection returned by
  [`entropia_connect()`](https://humalab.github.io/EntropIA-R/reference/entropia_connect.md).

- target_type:

  Optional character vector of target types to keep, or `NULL` (default)
  for all.

- job_type:

  Optional character vector of job types to keep, or `NULL` (default)
  for all.

## Value

A `tbl_sql` on `llm_results`.

## Details

Two optional filters, both pushed down to SQL:

- `target_type`: keep only rows whose target is one of the given types.
  On databases that predate migration 0019 the column does not exist and
  passing a filter errors with guidance; without a filter the accessor
  still reads the table.

- `job_type`: keep only rows for one or more job types.

## Examples

``` r
con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
  package = "entropiaR"
))
entropia_collect(entropia_llm_results(con))
#> # A tibble: 1 × 6
#>   id             target_id target_type job_type result       created_at         
#>   <chr>          <chr>     <chr>       <chr>    <list>       <dttm>             
#> 1 llr-item-2222… 22222222… item        summary  <named list> 2026-01-15 12:11:40
entropia_collect(entropia_llm_results(con, target_type = "item"))
#> # A tibble: 1 × 6
#>   id             target_id target_type job_type result       created_at         
#>   <chr>          <chr>     <chr>       <chr>    <list>       <dttm>             
#> 1 llr-item-2222… 22222222… item        summary  <named list> 2026-01-15 12:11:40
entropia_disconnect(con)
```
