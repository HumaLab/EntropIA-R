# Delete rows (v2 contract; errors in v1)

The write API is designed for v2 and shipped in v1 as stubs that error
with class `entropia_error_write_disabled`. Every call aborts
immediately with guidance: v1 is read-only, and write support arrives in
v2 via `entropia_connect(path, write = TRUE)`.

## Usage

``` r
entropia_delete(con, table, filter, all = FALSE, confirm = FALSE)
```

## Arguments

- con:

  An EntropIA connection.

- table:

  Table name.

- filter:

  A predicate identifying the rows to delete (required in v2; a
  full-table delete needs `all = TRUE`).

- all:

  Logical. In v2, permit a full-table delete when `TRUE` (default
  `FALSE`).

- confirm:

  Logical. In v2, must be `TRUE` for a delete to run.

## Value

Never returns: aborts with `entropia_error_write_disabled`.

## Details

In v2, `entropia_delete()` deletes rows matched by `filter` inside a
transaction. A full-table delete is refused unless `all = TRUE`, and
every delete requires `confirm = TRUE`.

## Examples

``` r
con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
  package = "entropiaR"
))
err <- tryCatch(entropia_delete(con, "items", id == "x", confirm = TRUE),
  error = identity
)
class(err) # "entropia_error_write_disabled"
#> [1] "entropia_error_write_disabled" "rlang_error"                  
#> [3] "error"                         "condition"                    
conditionMessage(err)
#> [1] "\033[1m\033[22m`entropia_delete()` is not available in entropiaR v1.\n\033[36mℹ\033[39m v1 is read-only: the database may be live in EntropIA (WAL) and is protected\n  by 81 sync/activity triggers.\n\033[36mℹ\033[39m Write support ships in v2, where you open the database for writing with\n  `entropia_connect()` (`path`, `write = TRUE`).\n\033[36mℹ\033[39m The v2 write design is documented in \033[34mvignettes/administration.Rmd\033[39m."
entropia_disconnect(con)
```
