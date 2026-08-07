# Convert timestamps to `POSIXct` with a magnitude guard

Pure helper for columns whose unit is not guaranteed (currently
`entities.created_at` and `triples.created_at`, whose DDL default is
epoch seconds but which the app writes in milliseconds). Values below
`1e12` are treated as epoch seconds, everything else as epoch
milliseconds – the same guard EntropIA migration 0019 used.

## Usage

``` r
entropia_datetime_auto(x)
```

## Arguments

- x:

  A numeric (or `integer64`) vector of timestamps.

## Value

A `POSIXct` vector (UTC).

## Examples

``` r
entropia_datetime_auto(1768478400) # seconds
#> [1] "2026-01-15 12:00:00 UTC"
entropia_datetime_auto(1768478400000) # milliseconds
#> [1] "2026-01-15 12:00:00 UTC"
```
