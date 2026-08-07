# Temporal profile (counts by time bucket)

**\[experimental\]**

## Usage

``` r
entropia_temporal_profile(x, date_var, unit = "month", by = NULL)
```

## Arguments

- x:

  A data frame or tibble of collected rows.

- date_var:

  A column of `POSIXct` (or `Date`) timestamps, selected by name or bare
  (tidyselect).

- unit:

  The time bucket: `"second"`, `"minute"`, `"hour"`, `"day"`, `"week"`
  (Monday-start), `"month"`, `"quarter"` or `"year"`. Default `"month"`.

- by:

  Optional column(s) to break the counts by, selected by name or bare
  (tidyselect). `NULL` (default) produces a single time series.

## Value

A tibble with the bucket column, the `by` columns (when given), and a
count column `n`.

## Details

Counts the rows of a collected tibble by a date/time column, bucketed to
a chosen time unit. This is an R-side analysis helper: pass a
materialised tibble (e.g. the output of
[`entropia_collect()`](https://humalab.github.io/EntropIA-R/reference/entropia_collect.md),
where timestamps are `POSIXct`). `NA` timestamps are excluded – a row
with an unknown date cannot be placed in time; grouping columns from
`by` keep `NA` as their own group, following `dplyr` semantics.

The returned bucket column carries the name of `date_var` and holds the
start of each unit (`POSIXct`, e.g. midnight for `unit = "day"`). Rows
are ordered by the `by` columns then the bucket, deterministically.
Weeks start on Monday.

## Examples

``` r
con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
  package = "entropiaR"
))
items <- entropia_collect(entropia_items(con))
entropia_temporal_profile(items, created_at, unit = "month")
#> # A tibble: 1 × 2
#>   created_at              n
#>   <dttm>              <int>
#> 1 2026-01-01 00:00:00     3
entropia_disconnect(con)
```
