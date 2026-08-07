# Update rows (v2 contract; errors in v1)

The write API is designed for v2 and shipped in v1 as stubs that error
with class `entropia_error_write_disabled`. Every call aborts
immediately with guidance: v1 is read-only, and write support arrives in
v2 via `entropia_connect(path, write = TRUE)`.

## Usage

``` r
entropia_update(con, table, data, by, dry_run = TRUE)
```

## Arguments

- con:

  An EntropIA connection.

- table:

  Table name.

- data:

  Data to write.

- by:

  Column name(s) identifying the rows to update (required in v2).

- dry_run:

  Logical. In v2, validate without writing when `TRUE` (default).

## Value

Never returns: aborts with `entropia_error_write_disabled`.

## Details

In v2, `entropia_update()` updates rows matched by `by` (required)
inside a transaction and never rewrites primary keys.

## Examples

``` r
con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
  package = "entropiaR"
))
err <- tryCatch(entropia_update(con, "items", data.frame(id = "x"), by = "id"),
  error = identity
)
class(err) # "entropia_error_write_disabled"
#> [1] "entropia_error_write_disabled" "rlang_error"                  
#> [3] "error"                         "condition"                    
conditionMessage(err)
#> [1] "\033[1m\033[22m`entropia_update()` is not available in entropiaR v1.\n\033[36mℹ\033[39m v1 is read-only: the database may be live in EntropIA (WAL) and is protected\n  by 81 sync/activity triggers.\n\033[36mℹ\033[39m Write support ships in v2, where you open the database for writing with\n  `entropia_connect()` (`path`, `write = TRUE`).\n\033[36mℹ\033[39m The v2 write design is documented in \033[34mvignettes/administration.Rmd\033[39m."
entropia_disconnect(con)
```
