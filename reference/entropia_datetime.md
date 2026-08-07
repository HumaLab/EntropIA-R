# Convert epoch-millisecond timestamps to `POSIXct`

Pure helper converting epoch-millisecond timestamps (13-digit integers,
as stored in `created_at`/`updated_at` on most EntropIA tables) to
`POSIXct` in the UTC timezone. Handles `integer64` vectors as returned
by RSQLite.

## Usage

``` r
entropia_datetime(x)
```

## Arguments

- x:

  A numeric (or `integer64`) vector of epoch-millisecond timestamps.

## Value

A `POSIXct` vector (UTC).

## Examples

``` r
entropia_datetime(1768478460000)
#> [1] "2026-01-15 12:01:00 UTC"
```
