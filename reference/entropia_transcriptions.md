# Transcriptions (lazy)

A lazy [`dplyr::tbl()`](https://dplyr.tidyverse.org/reference/tbl.html)
over the `transcriptions` table. Each row is the audio transcription of
one asset; `id` is deterministic (`trx-{asset_id}`) and `asset_id` is
UNIQUE (1:1 with
[`entropia_assets()`](https://humalab.github.io/EntropIA-R/reference/entropia_assets.md)).
The `segments` column is JSON-in-TEXT (array of
`{start_ms, end_ms, text}`); it stays raw until
[`entropia_collect()`](https://humalab.github.io/EntropIA-R/reference/entropia_collect.md)
applies the column contract.

## Usage

``` r
entropia_transcriptions(con)
```

## Arguments

- con:

  A connection returned by
  [`entropia_connect()`](https://humalab.github.io/EntropIA-R/reference/entropia_connect.md).

## Value

A `tbl_sql` on `transcriptions`.

## Examples

``` r
con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
  package = "entropiaR"
))
entropia_collect(entropia_transcriptions(con)) # segments -> list-column
#> # A tibble: 1 × 9
#>   id        asset_id text_content language duration_ms model segments confidence
#>   <chr>     <chr>    <chr>        <chr>          <int> <chr> <list>        <dbl>
#> 1 trx-3333… 3333333… Compañeros,… es             60000 whis… <df>           0.95
#> # ℹ 1 more variable: created_at <dttm>
entropia_disconnect(con)
```
