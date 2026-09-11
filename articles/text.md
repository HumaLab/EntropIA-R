# Extraer textos y metadatos

*Versión en español.* English:
[`vignette("text.en")`](https://humalab.github.io/EntropIA-R/articles/text.en.md).

## Capas de texto

Un asset puede tener hasta tres capas, 1:1 con `assets`:

| Tabla | Significado | Columnas principales |
|----|----|----|
| `extractions` | OCR / texto de PDF | `text_content`, `method`, `confidence` |
| `transcriptions` | Audio a texto | `text_content`, `language`, `duration_ms`, `segments` |
| `layouts` | Análisis de layout | `regions`, `blocks`, `image_width`, `image_height` |

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

## El mejor texto por asset

[`entropia_text()`](https://humalab.github.io/EntropIA-R/reference/entropia_text.md)
devuelve una fila por asset con una columna `text`. `source`:

- `"extraction"` — solo OCR/PDF;
- `"transcription"` — solo transcripción;
- `"auto"` (defecto) — extracción **si esa capa existe**, aunque el
  texto esté vacío; si no, transcripción. Es la regla `COALESCE` del
  corpus. Las métricas de “alguna capa útil” están en
  `entropia_overview()$quality`.

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

Assets sin capa conservan la fila con `text = NA`:

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

## Marcadores OCR

La extracción de PDF inserta `![](page=n,bbox=[...])`.
[`entropia_text()`](https://humalab.github.io/EntropIA-R/reference/entropia_text.md)
los saca por defecto (CTE recursivo en SQL, sigue perezoso):

``` r

raw <- entropia_text(con, strip_markers = FALSE) |> entropia_collect()
raw$text[1]
#> [1] "![](page=1,bbox=[10,10,500,700]) La huelga general de 1920 movilizo a los obreros."
```

``` r

clean <- entropia_text(con) |> entropia_collect()
clean$text[1]
#> [1] " La huelga general de 1920 movilizo a los obreros."
```

## Restringir a ciertos assets

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

## JSON a list-columns

[`entropia_collect()`](https://humalab.github.io/EntropIA-R/reference/entropia_collect.md)
aplica el contrato. `transcriptions.segments` vuelve como lista de data
frames:

``` r

trx <- entropia_transcriptions(con) |> entropia_collect()
trx$segments[[1]]
#>   start_ms end_ms        text
#> 1        0   2500  Compañeros
#> 2     2500   5000 a la huelga
```

## Metadatos

Campos no escalares de file-metadata ya no abortan el lote: se conserva
la fila, el JSON original en `raw_metadata`, y
`attr(..., "diagnostics")` lista `item_id`, campo y problema.

``` r

entropia_metadata(con)
#> # A tibble: 3 × 7
#>   item_id           original_name original_path imported_at         raw_metadata
#>   <chr>             <chr>         <chr>         <dttm>              <chr>       
#> 1 22222222-2222-42… manifiesto.p… /docs/manifi… 2026-01-15 12:05:00 "{\"__entro…
#> 2 22222222-2222-42… carta.mp3     /docs/carta.… 2026-01-15 12:06:00 "{\"__entro…
#> 3 22222222-2222-42… NA            NA            NA                   NA         
#> # ℹ 2 more variables: extra_metadata <list>, page_count <list>
```

JSON malformado avisa (con fila) y da `NA`. `parse = FALSE` deja el
texto crudo.

## Cobertura

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
```

``` r

entropia_disconnect(con)
```

Siguiente:
[`vignette("dplyr")`](https://humalab.github.io/EntropIA-R/articles/dplyr.md).
English:
[`vignette("text.en")`](https://humalab.github.io/EntropIA-R/articles/text.en.md).
