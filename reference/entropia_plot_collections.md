# Plot collection counts

Collection IDs are shown alongside names so identical names never merge.

## Usage

``` r
entropia_plot_collections(x, value = "n_items")
```

## Arguments

- x:

  Materialised collection summary with `collection_id` and
  `collection_name` columns.

- value:

  Numeric column, bare or named; defaults to `n_items`.

## Value

An extendible `ggplot` object.
