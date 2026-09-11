# Análisis exploratorio de un corpus EntropIA

*Versión en español.* English:
[`vignette("eda.en")`](https://humalab.github.io/EntropIA-R/articles/eda.en.md).

Empezá con un snapshot y un solo overview. No bajes el corpus completo
hasta que los recuentos confirmen el universo.

``` r

con <- entropia_connect(system.file(
  "extdata", "entropia-example.sqlite",
  package = "entropiaR"
))
```

## Inventario sin cargar texto

[`entropia_overview()`](https://humalab.github.io/EntropIA-R/reference/entropia_overview.md)
agrega en SQLite. Nunca materializa OCR, JSON ni BLOB.

``` r

eda <- entropia_overview(con)
names(eda)
#>  [1] "counts"      "collections" "asset_types" "temporal"    "quality"    
#>  [6] "entities"    "topics"      "inventory"   "selection"   "provenance"
eda$counts
#> # A tibble: 5 × 3
#>   metric               unit           n
#>   <chr>                <chr>      <int>
#> 1 items                item           3
#> 2 assets               asset          5
#> 3 collections          collection     1
#> 4 items_without_assets item           0
#> 5 pages                asset          2
eda$collections
#> # A tibble: 1 × 5
#>   collection_id                        collection_name   n_items n_assets     n
#>   <chr>                                <chr>               <int>    <int> <int>
#> 1 11111111-1111-4111-8111-111111111111 Archivo de prueba       3        5     5
eda$asset_types
#> # A tibble: 3 × 2
#>   asset_type     n
#>   <chr>      <int>
#> 1 audio          1
#> 2 image          1
#> 3 pdf            3
```

`counts` declara unidad (`item`, `asset`, `collection`). El `n` de
`collections` es filas de la consulta de estudio (assets más ítems sin
asset), no un sinónimo de `n_items`.

## Un universo, muchas tablas

``` r

pdfs <- entropia_overview(con, asset_types = "pdf", page_assets = FALSE)
pdfs$counts
#> # A tibble: 5 × 3
#>   metric               unit           n
#>   <chr>                <chr>      <int>
#> 1 items                item           1
#> 2 assets               asset          1
#> 3 collections          collection     1
#> 4 items_without_assets item           0
#> 5 pages                asset          0
pdfs$selection
#> $collection_ids
#> NULL
#> 
#> $asset_types
#> [1] "pdf"
#> 
#> $page_assets
#> [1] FALSE
#> 
#> $date_var
#> [1] "item_created_at"
#> 
#> $date_range
#> NULL
#> 
#> $text_source
#> [1] "auto"
#> 
#> $entity_source
#> NULL
#> 
#> $model_name
#> NULL
#> 
#> $min_confidence
#> NULL
```

Un vector de IDs vacío no selecciona “todo”: selecciona nada.

``` r

entropia_overview(con, collection_ids = character())$counts
#> # A tibble: 5 × 3
#>   metric               unit           n
#>   <chr>                <chr>      <int>
#> 1 items                item           0
#> 2 assets               asset          0
#> 3 collections          collection     0
#> 4 items_without_assets item           0
#> 5 pages                asset          0
```

## Calidad: numerador, denominador, status

``` r

eda$quality
#> # A tibble: 23 × 8
#>    metric            group_id              group unit      n total    pct status
#>    <chr>             <chr>                 <chr> <chr> <dbl> <dbl>  <dbl> <chr> 
#>  1 any_layer_usable  audio                 audio asset     1     1  1     ok    
#>  2 any_layer_usable  image                 image asset     0     1  0     ok    
#>  3 any_layer_usable  pdf                   pdf   asset     2     3  0.667 ok    
#>  4 empty_text        audio                 audio asset     0     1  0     ok    
#>  5 empty_text        image                 image asset     0     0 NA     no_da…
#>  6 empty_text        pdf                   pdf   asset     0     2  0     ok    
#>  7 metadata_coverage 11111111-1111-4111-8… Arch… item      2     3  0.667 ok    
#>  8 metadata_validity 11111111-1111-4111-8… Arch… item      2     2  1     ok    
#>  9 ocr_coverage      audio                 audio asset     0     1  0     ok    
#> 10 ocr_coverage      image                 image asset     0     1  0     ok    
#> # ℹ 13 more rows
```

Leé `status` antes que `pct`:

- `ok` — la tasa está definida;
- `empty` — hay filas elegibles pero el campo/capa está vacío;
- `no_data` — denominador 0;
- `not_applicable` — la métrica no aplica a ese grupo;
- `invalid` — JSON que no parsea.

`metadata_coverage` es *presencia* de texto. `metadata_validity` es
sintaxis JSON, no “el documento tiene autor y fecha”.

## Entidades y temas: ocurrencia vs prevalencia

``` r

eda$entities
#> # A tibble: 3 × 6
#>   entity_type  value                     n n_items total   pct
#>   <chr>        <chr>                 <int>   <int> <int> <dbl>
#> 1 organization Sindicato Ferroviario     1       1     3 0.333
#> 2 person       Juan Pérez                1       1     3 0.333
#> 3 place        Plaza de Mayo             1       1     3 0.333
eda$topics
#> # A tibble: 2 × 5
#>   name          n n_items total   pct
#>   <chr>     <int>   <int> <int> <dbl>
#> 1 HUELGA        1       1     3 0.333
#> 2 SINDICATO     1       1     3 0.333
```

`n` son menciones (filas). `n_items` son ítems distintos. `pct` es
`n_items / total` con `total` = ítems del universo — los ítems sin
entidad siguen en el denominador.

## Tiempo y exclusiones

``` r

eda$temporal
#> # A tibble: 1 × 2
#>   date                    n
#>   <dttm>              <int>
#> 1 2026-01-01 00:00:00     5
attr(eda$temporal, "exclusions")
#> # A tibble: 1 × 2
#>   missing invalid
#>     <int>   <int>
#> 1       0       0
```

Los buckets son inicios de mes UTC de `date_var` (defecto
`item_created_at`). Esa fecha es **operativa** (alta/importación), no
necesariamente la del documento histórico.

## Perfil de un tibble recolectado

``` r

lengths <- entropia_text(con) |>
  entropia_collect() |>
  entropia_document_lengths()
entropia_profile(lengths, columns = c("n_chars", "n_words"))
#> $structure
#> # A tibble: 2 × 8
#>   variable class   type        n n_missing min   max   contract
#>   <chr>    <chr>   <chr>   <int>     <int> <chr> <chr> <chr>   
#> 1 n_chars  integer integer     5         2 NA    NA    raw     
#> 2 n_words  integer integer     5         2 NA    NA    raw     
#> 
#> $missing
#> # A tibble: 2 × 5
#>   variable     n total   pct status
#>   <chr>    <int> <int> <dbl> <chr> 
#> 1 n_chars      2     5   0.4 ok    
#> 2 n_words      2     5   0.4 ok    
#> 
#> $numeric
#> # A tibble: 20 × 3
#>    variable statistic value
#>    <chr>    <chr>     <dbl>
#>  1 n_chars  n          3   
#>  2 n_chars  mean      42.3 
#>  3 n_chars  sd        16.9 
#>  4 n_chars  min       23   
#>  5 n_chars  q25       36.5 
#>  6 n_chars  median    50   
#>  7 n_chars  q75       52   
#>  8 n_chars  max       54   
#>  9 n_chars  IQR       15.5 
#> 10 n_chars  outliers   0   
#> 11 n_words  n          3   
#> 12 n_words  mean       6.67
#> 13 n_words  sd         2.52
#> 14 n_words  min        4   
#> 15 n_words  q25        5.5 
#> 16 n_words  median     7   
#> 17 n_words  q75        8   
#> 18 n_words  max        9   
#> 19 n_words  IQR        2.5 
#> 20 n_words  outliers   0   
#> 
#> $categorical
#> # A tibble: 0 × 5
#> # ℹ 5 variables: variable <chr>, value <chr>, n <int>, total <int>, pct <dbl>
#> 
#> $duplicates
#> # A tibble: 1 × 5
#>   rule           n n_groups n_rows total
#>   <chr>      <int>    <int>  <int> <int>
#> 1 exact_rows     1        1      2     5
#> 
#> $sampling
#> $sampling$original_n
#> [1] 5
#> 
#> $sampling$n
#> [1] 5
#> 
#> $sampling$sample_n
#> NULL
#> 
#> $sampling$sampled
#> [1] FALSE
#> 
#> $sampling$seed
#> NULL
#> 
#> $sampling$row_indices
#> [1] 1 2 3 4 5
```

El muestreo es opt-in y no cambia `.Random.seed`:

``` r

set.seed(1)
before <- .Random.seed
entropia_profile(lengths, sample_n = 2, seed = 99)$sampling$n
#> [1] 2
identical(.Random.seed, before)
#> [1] TRUE
```

El mismo objeto `eda` alimenta ggplot, el dashboard y
[`entropia_report()`](https://humalab.github.io/EntropIA-R/reference/entropia_report.md).

``` r

entropia_disconnect(con)
```

Siguiente:
[`vignette("visualize")`](https://humalab.github.io/EntropIA-R/articles/visualize.md).
English:
[`vignette("eda.en")`](https://humalab.github.io/EntropIA-R/articles/eda.en.md).
