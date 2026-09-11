# Plot topic frequencies

Rows remain separate, including repeated topic names in different
groups. The largest `top` rows are selected globally; ties follow input
order.

## Usage

``` r
entropia_plot_topics(x, top = 10, group = NULL, value = "n")
```

## Arguments

- x:

  Materialised topic summary with `name` and a numeric value column.

- top:

  Positive integer number of rows to display.

- group:

  Optional grouping column, bare or named. IDs take precedence over
  corresponding display names. Ambiguous automatic grouping errors.

- value:

  Numeric column, bare or named; defaults to `n`.

## Value

An extendible `ggplot` object. No database queries are performed.
