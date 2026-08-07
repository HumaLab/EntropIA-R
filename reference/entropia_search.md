# Search the full-text index

Parameter-safe FTS5 search over the `items` or `chunks` index. The query
is escaped with
[`DBI::dbQuoteString()`](https://dbi.r-dbi.org/reference/dbQuoteString.html)
before splicing into `MATCH`, so user input can never break out of the
string literal (injection-safe). Results are returned as a lazy
[`dplyr::tbl()`](https://dplyr.tidyverse.org/reference/tbl.html) ordered
by BM25 rank (best first); nothing is fetched until you collect.

## Usage

``` r
entropia_search(con, query, index = c("items", "chunks"), limit = NULL)
```

## Arguments

- con:

  A connection returned by
  [`entropia_connect()`](https://humalab.github.io/EntropIA-R/reference/entropia_connect.md).

- query:

  A single non-empty search string.

- index:

  Which FTS5 index to search: `"items"` (default) or `"chunks"`.

- limit:

  Maximum number of results. `NULL` (the default) returns all matches.

## Value

A `tbl_sql`. The `items` index returns item rows (via the
`fts_items.rowid = items.rowid` join) plus a `rank` column; the `chunks`
index returns `rag_chunks` rows plus `rank`.

## Details

The `items` index is the contentless `fts_items` table, so the join to
`items` on `rowid` is mandatory: searching without it would read `NULL`
in every declared column. The `chunks` index joins
`rag_chunks_fts.chunk_id` to `rag_chunks.id`; the `embedding` BLOB is
never selected (BLOB discipline).

## Examples

``` r
con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
  package = "entropiaR"
))
entropia_collect(entropia_search(con, "huelga"))
#> # A tibble: 2 × 8
#>   id     title collection_id metadata created_at updated_at search_text     rank
#>   <chr>  <chr> <chr>         <chr>       <int64>    <int64> <chr>          <dbl>
#> 1 22222… Mani… 11111111-111… "{\"__e…      1.e12      1.e12 "Manifiest… -1.10e-6
#> 2 22222… Cart… 11111111-111… "{\"__e…      1.e12      1.e12 "Carta al … -1.01e-6
entropia_collect(entropia_search(con, "huelga", index = "chunks", limit = 5))
#> # A tibble: 1 × 15
#>   id           asset_id item_id source_kind source_id chunk_ordinal text_content
#>   <chr>        <chr>    <chr>   <chr>       <chr>             <int> <chr>       
#> 1 ragchk-0000… 3333333… 222222… extraction  ext-3333…             0 La huelga g…
#> # ℹ 8 more variables: start_char <int>, end_char <int>, source_text_hash <chr>,
#> #   chunking_contract <chr>, embedding_model <chr>, embedding_contract <chr>,
#> #   dimensions <int>, rank <dbl>
entropia_disconnect(con)
```
