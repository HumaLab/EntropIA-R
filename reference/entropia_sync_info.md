# Whitelisted sync settings as a typed tibble

Reads the sync engine's `sync_meta` key/value table and returns only the
whitelisted keys – the ones that describe sync identity and freshness –
coerced to their natural R types. `last_sync_at` (epoch milliseconds) is
returned as `POSIXct`; `server_epoch` stays character (the app stores a
server/session identifier string, not a numeric epoch);
`triggers_version` as an integer; `capture_enabled` as a logical.

## Usage

``` r
entropia_sync_info(con)
```

## Arguments

- con:

  A connection returned by
  [`entropia_connect()`](https://humalab.github.io/EntropIA-R/reference/entropia_connect.md).

## Value

A one-row tibble with columns `device_id`, `account_email`,
`server_url`, `last_sync_at`, `server_epoch`, `triggers_version` and
`capture_enabled`. Keys absent from the database are `NA` of the correct
type.

## Details

`app_settings` is never part of this surface: it stores API secrets
(`*_api_key`) and is deliberately not surfaced raw.

## Examples

``` r
con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
  package = "entropiaR"
))
entropia_sync_info(con)
#> # A tibble: 1 × 7
#>   device_id      account_email       server_url last_sync_at        server_epoch
#>   <chr>          <chr>               <chr>      <dttm>              <chr>       
#> 1 device-fixture fixture@entropia.e… https://c… 2026-01-15 12:13:20 c3f5e8a0-11…
#> # ℹ 2 more variables: triggers_version <int>, capture_enabled <lgl>
entropia_disconnect(con)
```
