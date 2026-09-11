# Combined corpus quality report

A compact long-form report over the corpus, one row per `metric` x
`group` (group is an asset type for the per-type metrics and a
collection name for metadata):

## Usage

``` r
entropia_corpus_quality(con)
```

## Arguments

- con:

  A connection returned by
  [`entropia_connect()`](https://humalab.github.io/EntropIA-R/reference/entropia_connect.md).

## Value

A plain tibble with columns `metric`, `group_id`, `group`, `unit`, `n`,
`total`, `pct` and `status` (`ok` or `no_data`).

## Details

- `ocr_coverage`: `n` assets with a non-empty OCR extraction, `total`
  assets, per asset type.

- `transcription_presence`: `n` assets with a transcription, `total`
  assets, per asset type.

- `metadata_coverage`: `n` items with metadata, `total` items, per
  collection.

- `empty_text`: `n` assets with a text layer but no useful text in any
  layer, `total` assets with at least one text layer, per asset type.
  This legacy metric is not selected-source emptiness; see
  [`entropia_overview()`](https://humalab.github.io/EntropIA-R/reference/entropia_overview.md)
  for separate selected-source diagnostics.

`pct` is `n / total`, `NA` when `total` is 0. Collection IDs are
retained even when collection labels coincide. For a filtered study
universe, use
[`entropia_overview()`](https://humalab.github.io/EntropIA-R/reference/entropia_overview.md)
and its `quality` element.

## Examples

``` r
con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
  package = "entropiaR"
))
entropia_corpus_quality(con)
#> # A tibble: 10 × 8
#>    metric                 group_id         group unit      n total    pct status
#>    <chr>                  <chr>            <chr> <chr> <int> <int>  <dbl> <chr> 
#>  1 empty_text             audio            audio asset     0     1  0     ok    
#>  2 empty_text             image            image asset     0     0 NA     no_da…
#>  3 empty_text             pdf              pdf   asset     0     2  0     ok    
#>  4 metadata_coverage      11111111-1111-4… Arch… item      2     3  0.667 ok    
#>  5 ocr_coverage           audio            audio asset     0     1  0     ok    
#>  6 ocr_coverage           image            image asset     0     1  0     ok    
#>  7 ocr_coverage           pdf              pdf   asset     2     3  0.667 ok    
#>  8 transcription_presence audio            audio asset     1     1  1     ok    
#>  9 transcription_presence image            image asset     0     1  0     ok    
#> 10 transcription_presence pdf              pdf   asset     0     3  0     ok    
entropia_disconnect(con)
```
