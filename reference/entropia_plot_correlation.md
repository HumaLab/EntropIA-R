# Plot correlations of selected numeric measurements

Uses pairwise complete finite observations and Pearson correlation.
Columns named `id` or ending in `_id` (case insensitive), dates and
nonnumeric columns are excluded. Constant columns and pairs with fewer
than two observations are annotated as undefined, not replaced by zero.

## Usage

``` r
entropia_plot_correlation(x, columns)
```

## Arguments

- x:

  A materialised data frame.

- columns:

  Explicit tidyselect selection of candidate measurements.

## Value

An extendible `ggplot` object.
