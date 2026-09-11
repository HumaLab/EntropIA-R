# Plot two numeric measurements

Plot two numeric measurements

## Usage

``` r
entropia_plot_scatter(x, x_var, y_var, by = NULL)
```

## Arguments

- x:

  A materialised data frame.

- x_var, y_var:

  Numeric measurement columns, bare or named.

- by:

  Optional grouping column, bare or named.

## Value

An extendible `ggplot` object. Non-finite pairs are explicitly counted
in the caption; an empty selection produces an annotation.
