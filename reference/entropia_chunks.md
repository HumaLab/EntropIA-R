# RAG chunks (lazy)

A lazy [`dplyr::tbl()`](https://dplyr.tidyverse.org/reference/tbl.html)
over the `rag_chunks` table: chunked text with embeddings for retrieval.
The chunking contract is exposed as columns (`chunking_contract`,
`embedding_model`, `embedding_contract`, `dimensions`). The `embedding`
BLOB is omitted by default; pass `with_vector = TRUE` to select it.

## Usage

``` r
entropia_chunks(con, with_vector = FALSE)
```

## Arguments

- con:

  A connection returned by
  [`entropia_connect()`](https://humalab.github.io/EntropIA-R/reference/entropia_connect.md).

- with_vector:

  Include the `embedding` BLOB column. Default `FALSE`.

## Value

A `tbl_sql` on `rag_chunks`.

## Examples

``` r
con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
  package = "entropiaR"
))
entropia_collect(entropia_chunks(con)) # chunking contract columns exposed
#> # A tibble: 1 × 14
#>   id           asset_id item_id source_kind source_id chunk_ordinal text_content
#>   <chr>        <chr>    <chr>   <chr>       <chr>             <int> <chr>       
#> 1 ragchk-0000… 3333333… 222222… extraction  ext-3333…             0 La huelga g…
#> # ℹ 7 more variables: start_char <int>, end_char <int>, source_text_hash <chr>,
#> #   chunking_contract <chr>, embedding_model <chr>, embedding_contract <chr>,
#> #   dimensions <int>
entropia_collect(entropia_chunks(con, with_vector = TRUE))
#> # A tibble: 1 × 15
#>   id           asset_id item_id source_kind source_id chunk_ordinal text_content
#>   <chr>        <chr>    <chr>   <chr>       <chr>             <int> <chr>       
#> 1 ragchk-0000… 3333333… 222222… extraction  ext-3333…             0 La huelga g…
#> # ℹ 8 more variables: start_char <int>, end_char <int>, source_text_hash <chr>,
#> #   chunking_contract <chr>, embedding <blob>, embedding_model <chr>,
#> #   embedding_contract <chr>, dimensions <int>
entropia_disconnect(con)
```
