# Plot corpus coverage

Plots the output of
[`entropia_corpus_quality()`](https://humalab.github.io/EntropIA-R/reference/entropia_corpus_quality.md)
– coverage proportions per metric and group – as a bar chart. With a
single `metric` the chart is a plain bar chart of the coverage
proportion by group; with several metrics the bars are faceted by
`metric`, each panel carrying its own groups and y scale.

## Usage

``` r
entropia_plot_coverage(x, metric = NULL)
```

## Arguments

- x:

  A data frame or tibble with `metric`, `group` and `pct` columns, e.g.
  the output of
  [`entropia_corpus_quality()`](https://humalab.github.io/EntropIA-R/reference/entropia_corpus_quality.md).

- metric:

  Optional character vector of metric(s) to plot, a subset of
  `unique(x$metric)`. `NULL` (default) plots all metrics.

## Value

A `ggplot` object.

## Details

The y axis is labelled as a percentage. `pct` is `NA` for groups with no
total (e.g. a metric absent from a corpus); those bars are dropped by
`ggplot2` like any `NA` aesthetic.

## Examples

``` r
q <- data.frame(
  metric = c("ocr_coverage", "metadata_coverage"),
  group = c("image", "Archivo de prueba"),
  n = c(250L, 3L),
  total = c(2428L, 3L),
  pct = c(250 / 2428, 1)
)
p <- entropia_plot_coverage(q)
if (requireNamespace("ggplot2", quietly = TRUE)) {
  p + ggplot2::labs(title = "Coverage")
}
```
