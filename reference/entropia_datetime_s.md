# Convert epoch-second timestamps to `POSIXct`

Pure helper converting epoch-second timestamps (10-digit integers, as
used by `_migrations.applied_at`) to `POSIXct` in the UTC timezone.

## Usage

``` r
entropia_datetime_s(x)
```

## Arguments

- x:

  A numeric (or `integer64`) vector of epoch-second timestamps.

## Value

A `POSIXct` vector (UTC).

## Examples

``` r
entropia_datetime_s(1768478400)
#> [1] "2026-01-15 12:00:00 UTC"
```
