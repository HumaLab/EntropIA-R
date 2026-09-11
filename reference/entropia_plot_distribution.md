# Plot a numeric distribution

Non-finite observations are excluded with an explicit caption.
Logarithmic plots also exclude nonpositive observations. Histograms
overlay groups transparently rather than stacking their counts.

## Usage

``` r
entropia_plot_distribution(
  x,
  var,
  by = NULL,
  type = "histogram",
  bins = 30,
  log = FALSE
)
```

## Arguments

- x:

  A materialised data frame.

- var:

  Numeric measurement column, bare or named.

- by:

  Optional grouping column, bare or named.

- type:

  One of `histogram`, `ecdf`, or `boxplot`.

- bins:

  Positive integer number of histogram bins.

- log:

  Whether to use a base-10 logarithmic measurement axis.

## Value

An extendible `ggplot` object.
