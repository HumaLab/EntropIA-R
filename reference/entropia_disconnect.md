# Close an EntropIA connection

Closes a connection opened by
[`entropia_connect()`](https://humalab.github.io/EntropIA-R/reference/entropia_connect.md).
Idempotent: calling it again on an already-closed connection is a no-op.

## Usage

``` r
entropia_disconnect(con)
```

## Arguments

- con:

  An `entropia_conn` (or any DBI connection).

## Value

`con`, invisibly.

## Examples

``` r
con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
  package = "entropiaR"
))
entropia_disconnect(con)
entropia_disconnect(con) # idempotent: safe on a closed connection
```
