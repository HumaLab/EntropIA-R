# Asset embedding vectors (lazy)

A lazy [`dplyr::tbl()`](https://dplyr.tidyverse.org/reference/tbl.html)
over the `vec_assets` table (one row per embedded asset). The
`embedding` BLOB – a raw little-endian `f32` vector – is omitted by
default so query results stay small; pass `with_vector = TRUE` to select
it. The embedding contract columns (`embedding_model`,
`embedding_contract`, `dimensions`) arrived with migration 0028 and are
simply absent on older databases.

## Usage

``` r
entropia_embeddings(con, with_vector = FALSE)
```

## Arguments

- con:

  A connection returned by
  [`entropia_connect()`](https://humalab.github.io/EntropIA-R/reference/entropia_connect.md).

- with_vector:

  Include the `embedding` BLOB column. Default `FALSE`.

## Value

A `tbl_sql` on `vec_assets`.

## Examples

``` r
con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
  package = "entropiaR"
))
entropia_collect(entropia_embeddings(con)) # no embedding BLOB by default
#> # A tibble: 1 × 5
#>   asset_id                 item_id embedding_model embedding_contract dimensions
#>   <chr>                    <chr>   <chr>           <chr>                   <int>
#> 1 33333333-3333-4333-8333… 222222… baai/bge-m3     bge-m3-6000-char-…          4
entropia_collect(entropia_embeddings(con, with_vector = TRUE))
#> # A tibble: 1 × 6
#>   asset_id      item_id  embedding embedding_model embedding_contract dimensions
#>   <chr>         <chr>       <blob> <chr>           <chr>                   <int>
#> 1 33333333-333… 222222… <raw 16 B> baai/bge-m3     bge-m3-6000-char-…          4
entropia_disconnect(con)
```
