# Plot a temporal profile

Plots the output of
[`entropia_temporal_profile()`](https://humalab.github.io/EntropIA-R/reference/entropia_temporal_profile.md)
– counts per time bucket – as a line chart. The date column is
auto-detected when `x` carries exactly one `POSIXct`/`Date` column (the
bucket); pass `date_var` when the profile carries several date-like
columns (e.g. grouping columns that are themselves dates).

## Usage

``` r
entropia_plot_temporal(
  x,
  date_var = NULL,
  group = NULL,
  facet = NULL,
  value = "n"
)
```

## Arguments

- x:

  A data frame or tibble with a `n` count column and a date column, e.g.
  the output of
  [`entropia_temporal_profile()`](https://humalab.github.io/EntropIA-R/reference/entropia_temporal_profile.md).

- date_var:

  Optional date column to plot on the x axis, selected by name or bare
  (tidyselect). `NULL` (default) auto-detects the single date column of
  `x`.

- group:

  Optional grouping column, bare or named.

- facet:

  Optional faceting column, bare or named.

- value:

  Numeric measure column, bare or named; defaults to `n`.

## Value

A `ggplot` object.

## Details

The returned `ggplot` is deliberately bare: add labels, a title, a theme
or facets with `+`. Grouped summaries draw separate lines, preferring
IDs to display names. Automatic grouping requires a single unambiguous
remaining dimension; otherwise select `group` explicitly. Duplicate
dates within a series are rejected rather than joined or aggregated
silently.

## Examples

``` r
prof <- data.frame(
  created_at = as.POSIXct(c("2026-01-01", "2026-02-01"), tz = "UTC"),
  n = c(3L, 5L)
)
if (requireNamespace("ggplot2", quietly = TRUE)) {
  p <- entropia_plot_temporal(prof)
  p + ggplot2::labs(title = "Elementos a lo largo del tiempo")
}
```
