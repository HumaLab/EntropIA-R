# Per-asset best text (lazy)

Returns one row per asset with a `text` column holding the asset's best
available text layer:

## Usage

``` r
entropia_text(con, assets = NULL, source = "auto", strip_markers = TRUE)
```

## Arguments

- con:

  A connection returned by
  [`entropia_connect()`](https://github.com/HumaLab/EntropIA-R/reference/entropia_connect.md).

- assets:

  `NULL` for all assets, a character vector of asset ids to keep, or a
  lazy table of assets (must have an `id` column). Default `NULL`.

- source:

  Which text layer to use: `"auto"` (default), `"extraction"`, or
  `"transcription"`.

- strip_markers:

  Remove OCR page markers (`![](page=n,bbox=[...])`) from the text.
  Default `TRUE`.

## Value

A `tbl_sql` with the input asset columns plus `text`.

## Details

- `source = "extraction"`: the OCR extraction text
  (`extractions.text_content`).

- `source = "transcription"`: the audio transcription text
  (`transcriptions.text_content`).

- `source = "auto"` (default): the extraction text when the asset has
  one, otherwise the transcription text – the same rule the app uses to
  build its search index.

The selection is assembled in SQL (a single `COALESCE` expression over
the 1:1 extractions/transcriptions joins), so nothing is fetched until
you collect and there are no per-row R loops. Assets with neither layer
get `NA` text; they are still returned (left joins, one row per asset).
The returned columns are the input asset columns plus `text`.

Extraction text may embed OCR page markers of the form
`![](page=n,bbox=[...])`. With `strip_markers = TRUE` (default) they are
removed in SQL via a recursive query, so the result stays lazy and
composable with
[`dplyr::filter()`](https://dplyr.tidyverse.org/reference/filter.html) /
[`dplyr::select()`](https://dplyr.tidyverse.org/reference/select.html) /
friends. The marker itself is removed exactly; surrounding whitespace is
preserved.

## Examples

``` r
con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
  package = "entropiaR"
))
entropia_text(con)
#> # A query:  ?? x 10
#> # Database: sqlite 3.53.3 [/home/runner/work/_temp/Library/entropiaR/extdata/entropia-example.sqlite]
#>   id             item_id path  type   size created_at sort_index parent_asset_id
#>   <chr>          <chr>   <chr> <chr> <int>    <int64>      <int> <chr>          
#> 1 33333333-3333… 222222… stor… pdf   20480      1.e12          0 NA             
#> 2 33333333-3333… 222222… stor… pdf   10240      1.e12          1 33333333-3333-…
#> 3 33333333-3333… 222222… stor… pdf   10240      1.e12          2 33333333-3333-…
#> 4 33333333-3333… 222222… stor… image  5120      1.e12          0 NA             
#> 5 33333333-3333… 222222… stor… audio 40960      1.e12          0 NA             
#> # ℹ 2 more variables: page_number <int>, text <chr>
entropia_text(con, source = "extraction", strip_markers = TRUE)
#> # A query:  ?? x 10
#> # Database: sqlite 3.53.3 [/home/runner/work/_temp/Library/entropiaR/extdata/entropia-example.sqlite]
#>   id             item_id path  type   size created_at sort_index parent_asset_id
#>   <chr>          <chr>   <chr> <chr> <int>    <int64>      <int> <chr>          
#> 1 33333333-3333… 222222… stor… pdf   20480      1.e12          0 NA             
#> 2 33333333-3333… 222222… stor… pdf   10240      1.e12          1 33333333-3333-…
#> 3 33333333-3333… 222222… stor… pdf   10240      1.e12          2 33333333-3333-…
#> 4 33333333-3333… 222222… stor… image  5120      1.e12          0 NA             
#> 5 33333333-3333… 222222… stor… audio 40960      1.e12          0 NA             
#> # ℹ 2 more variables: page_number <int>, text <chr>
entropia_disconnect(con)
```
