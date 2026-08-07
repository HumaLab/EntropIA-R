# Extracting texts and metadata

## The text layers

An asset can have up to three machine-readable text layers, stored in
three 1:1 tables:

| Table | Meaning | Main columns |
|----|----|----|
| `extractions` | OCR / PDF text extraction | `text_content`, `method`, `confidence` |
| `transcriptions` | Speech-to-text for audio | `text_content`, `language`, `duration_ms`, `segments` |
| `layouts` | Layout analysis (regions/blocks) | `regions`, `blocks`, `image_width`, `image_height` |

Each row is keyed deterministically to its asset (`ext-`, `trx-`, `lay-`
plus the asset id), so the layer tables join 1:1 to `assets` with no
fan-out.

``` r

con <- entropia_connect(system.file("extdata", "entropia-example.sqlite", package = "entropiaR"))
entropia_extractions(con) |> entropia_collect()
#> # A tibble: 2 × 6
#>   id                 asset_id text_content method confidence created_at         
#>   <chr>              <chr>    <chr>        <chr>       <dbl> <dttm>             
#> 1 ext-33333333-3333… 3333333… ![](page=1,… ocr          0.91 2026-01-15 12:08:00
#> 2 ext-33333333-3333… 3333333… Segunda pag… pdf_p…       0.88 2026-01-15 12:08:10
entropia_transcriptions(con) |> entropia_collect()
#> # A tibble: 1 × 9
#>   id        asset_id text_content language duration_ms model segments confidence
#>   <chr>     <chr>    <chr>        <chr>          <int> <chr> <list>        <dbl>
#> 1 trx-3333… 3333333… Compañeros,… es             60000 whis… <df>           0.95
#> # ℹ 1 more variable: created_at <dttm>
entropia_layouts(con) |> entropia_collect()
#> # A tibble: 1 × 8
#>   id                      asset_id regions blocks model image_width image_height
#>   <chr>                   <chr>    <list>  <list> <chr>       <int>        <int>
#> 1 lay-33333333-3333-4333… 3333333… <df>    <df>   layo…        1000         1400
#> # ℹ 1 more variable: created_at <dttm>
```

## The best text per asset

[`entropia_text()`](https://github.com/HumaLab/EntropIA-R/reference/entropia_text.md)
returns one row per asset with a single `text` column — the best
available text per asset. `source` selects the layer:

- `"extraction"` — the OCR/PDF extraction text only;
- `"transcription"` — the audio transcription text only;
- `"auto"` (default) — extraction when present, otherwise transcription
  (this mirrors the rule EntropIA’s own full-text index uses).

``` r

entropia_text(con) |> entropia_collect()
#> # A tibble: 5 × 10
#>   id             item_id path  type   size created_at sort_index parent_asset_id
#>   <chr>          <chr>   <chr> <chr> <int>    <int64>      <int> <chr>          
#> 1 33333333-3333… 222222… stor… pdf   20480      1.e12          0 NA             
#> 2 33333333-3333… 222222… stor… pdf   10240      1.e12          1 33333333-3333-…
#> 3 33333333-3333… 222222… stor… pdf   10240      1.e12          2 33333333-3333-…
#> 4 33333333-3333… 222222… stor… image  5120      1.e12          0 NA             
#> 5 33333333-3333… 222222… stor… audio 40960      1.e12          0 NA             
#> # ℹ 2 more variables: page_number <int>, text <chr>
```

Assets with neither layer keep their row and get `NA` text:

``` r

entropia_text(con) |>
  entropia_collect() |>
  dplyr::filter(is.na(text))
#> # A tibble: 2 × 10
#>   id             item_id path  type   size created_at sort_index parent_asset_id
#>   <chr>          <chr>   <chr> <chr> <int>    <int64>      <int> <chr>          
#> 1 33333333-3333… 222222… stor… pdf   10240      1.e12          2 33333333-3333-…
#> 2 33333333-3333… 222222… stor… image  5120      1.e12          0 NA             
#> # ℹ 2 more variables: page_number <int>, text <chr>
```

## OCR markers

EntropIA’s PDF extraction embeds *image markers* in the text —
`![](page=n,bbox=[...])` — one per embedded page image. They are noise
for text analysis, so
[`entropia_text()`](https://github.com/HumaLab/EntropIA-R/reference/entropia_text.md)
strips them by default. See the raw text first:

``` r

raw <- entropia_text(con, strip_markers = FALSE) |> entropia_collect()
raw$text[1]
#> [1] "![](page=1,bbox=[10,10,500,700]) La huelga general de 1920 movilizo a los obreros."
```

And the stripped version:

``` r

clean <- entropia_text(con) |> entropia_collect()
clean$text[1]
#> [1] " La huelga general de 1920 movilizo a los obreros."
```

The stripping happens in SQL (a recursive CTE), so it stays lazy and
composable — you can `filter`/`mutate` on top of
[`entropia_text()`](https://github.com/HumaLab/EntropIA-R/reference/entropia_text.md)
and the whole query still runs on SQLite.

## Restricting to specific assets

`assets` accepts a character vector of asset ids or a lazy `tbl_sql`:

``` r

ids <- entropia_assets(con) |>
  dplyr::filter(type == "audio") |>
  dplyr::pull(id)
entropia_text(con, assets = ids) |> entropia_collect()
#> # A tibble: 1 × 10
#>   id             item_id path  type   size created_at sort_index parent_asset_id
#>   <chr>          <chr>   <chr> <chr> <int>    <int64>      <int> <chr>          
#> 1 33333333-3333… 222222… stor… audio 40960      1.e12          0 NA             
#> # ℹ 2 more variables: page_number <int>, text <chr>
```

## JSON columns become list-columns

[`entropia_collect()`](https://github.com/HumaLab/EntropIA-R/reference/entropia_collect.md)
applies the column contract. JSON-in-TEXT columns become list-columns
via `jsonlite`, so `transcriptions.segments` (an array of
`{start_ms, end_ms, text}` objects) comes back as a list of data frames:

``` r

trx <- entropia_transcriptions(con) |> entropia_collect()
trx$segments[[1]]
#>   start_ms end_ms        text
#> 1        0   2500  Compañeros
#> 2     2500   5000 a la huelga
```

The same applies to `items.metadata`, `rag_messages.sources`, and
`llm_results.result`.

## Metadata

[`entropia_metadata()`](https://github.com/HumaLab/EntropIA-R/reference/entropia_metadata.md)
parses `items.metadata` into tidy rows (see
[`vignette("corpus")`](https://github.com/HumaLab/EntropIA-R/articles/corpus.md)):

``` r

entropia_metadata(con)
#> # A tibble: 3 × 5
#>   item_id             original_name original_path imported_at         page_count
#>   <chr>               <chr>         <chr>         <dttm>              <list>    
#> 1 22222222-2222-4222… manifiesto.p… /docs/manifi… 2026-01-15 12:05:00 <int [1]> 
#> 2 22222222-2222-4222… carta.mp3     /docs/carta.… 2026-01-15 12:06:00 <NULL>    
#> 3 22222222-2222-4222… NA            NA            NA                  <NULL>
```

Malformed JSON never fails the collect — it warns and yields `NA`, and
the raw value stays reachable via `parse = FALSE`.

## Coverage at a glance

To see which assets are missing a text layer, use the coverage helpers:

``` r

entropia_ocr_coverage(con, by = "asset") |> entropia_collect()
#> # A tibble: 5 × 7
#>   asset_id       item_id asset_type collection_id collection_name has_extraction
#>   <chr>          <chr>   <chr>      <chr>         <chr>                    <int>
#> 1 33333333-3333… 222222… pdf        11111111-111… Archivo de pru…              1
#> 2 33333333-3333… 222222… pdf        11111111-111… Archivo de pru…              1
#> 3 33333333-3333… 222222… pdf        11111111-111… Archivo de pru…              0
#> 4 33333333-3333… 222222… image      11111111-111… Archivo de pru…              0
#> 5 33333333-3333… 222222… audio      11111111-111… Archivo de pru…              0
#> # ℹ 1 more variable: text_empty <int>
```

Or the combined quality report:

``` r

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
```

## Cleaning up

``` r

entropia_disconnect(con)
```

Next:
[`vignette("dplyr")`](https://github.com/HumaLab/EntropIA-R/articles/dplyr.md)
for composing lazy queries, or
[`vignette("datasets")`](https://github.com/HumaLab/EntropIA-R/articles/datasets.md)
for building reproducible analysis datasets.
