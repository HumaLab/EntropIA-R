# Plot missing-value proportions

Every variable/group row receives a separate bar. Undefined proportions
are annotated rather than represented as zero.

## Usage

``` r
entropia_plot_missing(x)
```

## Arguments

- x:

  The materialised `missing` tibble returned by
  [`entropia_profile()`](https://humalab.github.io/EntropIA-R/reference/entropia_profile.md).

## Value

An extendible `ggplot` object.
