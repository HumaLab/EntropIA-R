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
  [`entropia_connect()`](https://github.com/HumaLab/EntropIA-R/reference/entropia_connect.md).

## Value

A tibble of class `entropia_corpus_quality` with columns `metric`,
`group`, `n`, `total` and `pct`.

## Details

- `ocr_coverage`: `n` assets with a non-empty OCR extraction, `total`
  assets, per asset type.

- `transcription_presence`: `n` assets with a transcription, `total`
  assets, per asset type.

- `metadata_coverage`: `n` items with metadata, `total` items, per
  collection.

- `empty_text`: `n` assets whose best text layer is
  empty/whitespace-only, `total` assets with at least one text layer,
  per asset type.

`pct` is `n / total`, `NA` when `total` is 0. The report is materialised
(it is a small aggregate, like
[`entropia_validate()`](https://github.com/HumaLab/EntropIA-R/reference/entropia_validate.md)
findings) and carries the `entropia_corpus_quality` class.

## Examples

``` r
con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
  package = "entropiaR"
))
entropia_corpus_quality(con)
#> # A tibble: 10 × 5
#>    metric                 group                 n total    pct
#>    <chr>                  <chr>             <int> <int>  <dbl>
#>  1 empty_text             audio                 0     1  0    
#>  2 empty_text             image                 0     0 NA    
#>  3 empty_text             pdf                   0     2  0    
#>  4 metadata_coverage      Archivo de prueba     2     3  0.667
#>  5 ocr_coverage           audio                 0     1  0    
#>  6 ocr_coverage           image                 0     1  0    
#>  7 ocr_coverage           pdf                   2     3  0.667
#>  8 transcription_presence audio                 1     1  1    
#>  9 transcription_presence image                 0     1  0    
#> 10 transcription_presence pdf                   0     3  0    
entropia_disconnect(con)
```
