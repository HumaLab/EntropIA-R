# Plot entity frequencies

Plots the output of
[`entropia_entity_frequency()`](https://github.com/HumaLab/EntropIA-R/reference/entropia_entity_frequency.md)
as a horizontal bar chart of the top entity values, filled by a column
of `x` (by default `entity_type`). `value` is reordered by count so the
most frequent entity sits at the top of the chart (via `coord_flip()`).

## Usage

``` r
entropia_plot_entities(x, top = 10, fill = "entity_type")
```

## Arguments

- x:

  A data frame or tibble with `value` and `n` columns (and typically
  `entity_type`), e.g. the output of
  [`entropia_entity_frequency()`](https://github.com/HumaLab/EntropIA-R/reference/entropia_entity_frequency.md).

- top:

  Number of top rows (by `n`) to plot. Default `10`.

- fill:

  Column of `x` to colour the bars by, selected by name or bare. Default
  `"entity_type"`.

## Value

A `ggplot` object.

## Examples

``` r
freq <- data.frame(
  entity_type = c("person", "organization", "place"),
  value = c("Juan Pérez", "CGT", "Mar del Plata"),
  n = c(4L, 3L, 2L)
)
p <- entropia_plot_entities(freq)
if (requireNamespace("ggplot2", quietly = TRUE)) {
  p + ggplot2::labs(title = "Custom title")
}
```
