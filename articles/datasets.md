# Datasets de análisis reproducibles

*Versión en español.* English:
[`vignette("datasets.en")`](https://humalab.github.io/EntropIA-R/articles/datasets.en.md).

## Para qué sirve la procedencia

El corpus cambia: EntropIA sincroniza, el esquema evoluciona. Un
`filter` + `collect` suelto no dice *qué* datos produjeron un resultado.
[`entropia_analysis_dataset()`](https://humalab.github.io/EntropIA-R/reference/entropia_analysis_dataset.md)
sella esa frontera.

``` r

con <- entropia_connect(system.file("extdata", "entropia-example.sqlite", package = "entropiaR"))
```

## Armar un dataset

``` r

ds <- entropia_analysis_dataset(con, name = "pdf_documents", asset_type == "pdf")
#> Warning: Missing values are always removed in SQL aggregation functions.
#> Use `na.rm = TRUE` to silence this warning
#> This warning is displayed once every 8 hours.
ds
#> entropia_dataset: pdf_documents
#>   schema: 0029_rag_chunks  hash: 09d4c603b66d
#>   filters: asset_type == "pdf"
#> # A tibble: 3 × 19
#>   item_id              item_title collection_id metadata     item_created_at    
#>   <chr>                <chr>      <chr>         <list>       <dttm>             
#> 1 22222222-2222-4222-… Manifiest… 11111111-111… <named list> 2026-01-15 12:01:00
#> 2 22222222-2222-4222-… Manifiest… 11111111-111… <named list> 2026-01-15 12:01:00
#> 3 22222222-2222-4222-… Manifiest… 11111111-111… <named list> 2026-01-15 12:01:00
#> # ℹ 14 more variables: item_updated_at <dttm>, collection_name <chr>,
#> #   collection_description <chr>, collection_created_at <dttm>,
#> #   collection_updated_at <dttm>, asset_id <chr>, asset_path <chr>,
#> #   asset_type <chr>, asset_size <int>, asset_created_at <dttm>,
#> #   asset_sort_index <int>, parent_asset_id <chr>, page_number <int>,
#> #   text <chr>
```

El tibble lleva `entropia_prov` (sidecar v2): versión de esquema, hash
de esquema, digest del archivo fuente, digest canónico de filas, SQL
resuelto, receta de selección, ruta, filtros, versiones y `built_at`.

``` r

entropia_provenance(ds)
#> entropiaR dataset provenance
#>   name:           pdf_documents
#>   schema version: 0029_rag_chunks
#>   schema hash:    09d4c603b66d68c4c0cef0f51ff09a04fb30a49fe200907ef69693d11dd25732
#>   dataset hash:   1994ab82411fd92a1e09cf8caf392cb8720691b8d07903bad7d4bac1faa22ecf
#>   scope:          origin
#>   source path:    /home/runner/work/_temp/Library/entropiaR/extdata/entropia-example.sqlite
#>   filters:        asset_type == "pdf"
#>   package:        0.0.0.9000
#>   built at:       2026-09-11T18:08:00.908Z
#>   R version:      R version 4.6.1 (2026-06-24)
```

`unit = "item"` colapsa a una fila por documento; `text = FALSE` omite
OCR:

``` r

entropia_analysis_dataset(con, name = "audio_items", asset_type == "audio") |>
  nrow()
#> [1] 1
entropia_analysis_dataset(con, unit = "item", text = FALSE, name = "items_only") |>
  ncol()
#> [1] 9
```

## Determinismo

Misma entrada → mismas filas (orden `item_id` + `asset_id`):

``` r

a <- entropia_analysis_dataset(con, asset_type == "image")
b <- entropia_analysis_dataset(con, asset_type == "image")
identical(as.data.frame(a), as.data.frame(b))
#> [1] FALSE
identical(
  entropia_provenance(a)[["dataset_sha256"]],
  entropia_provenance(b)[["dataset_sha256"]]
)
#> [1] TRUE
```

Solo `built_at` cambia entre builds. `schema_hash` es identidad
estructural; `dataset_sha256` es identidad de datos. Sobre un objeto
*derivado*,
[`entropia_provenance()`](https://humalab.github.io/EntropIA-R/reference/entropia_provenance.md)
recalcula el digest, marca `scope = "derived"` y guarda origen en
`origin` — no afirma que el SQL original reproduzca las filas
transformadas.

## Sidecar JSON

``` r

prov_path <- tempfile(fileext = "-prov.json")
entropia_write_provenance(ds, prov_path)
entropia_write_provenance(ds, tempfile(fileext = "-redacted.json"), redact = TRUE)
readLines(prov_path)[1:9]
#> [1] "{"                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                
#> [2] "  \"sidecar_version\": 2,"                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        
#> [3] "  \"name\": \"pdf_documents\","                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   
#> [4] "  \"scope\": \"origin\","                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         
#> [5] "  \"schema_version\": \"0029_rag_chunks\","                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       
#> [6] "  \"schema_hash\": \"09d4c603b66d68c4c0cef0f51ff09a04fb30a49fe200907ef69693d11dd25732\","                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         
#> [7] "  \"snapshot_sha256\": \"4cb964df442cd35fe1cb6b56b7dadf63a02de92014b4a9334cdfe2de9615a34c\","                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     
#> [8] "  \"dataset_sha256\": \"1994ab82411fd92a1e09cf8caf392cb8720691b8d07903bad7d4bac1faa22ecf\","                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      
#> [9] "  \"query\": \"SELECT\\n  `item_id`,\\n  `item_title`,\\n  `collection_id`,\\n  `metadata`,\\n  `item_created_at`,\\n  `item_updated_at`,\\n  `collection_name`,\\n  `collection_description`,\\n  `collection_created_at`,\\n  `collection_updated_at`,\\n  `asset_id`,\\n  `asset_path`,\\n  `asset_type`,\\n  `asset_size`,\\n  `asset_created_at`,\\n  `asset_sort_index`,\\n  `parent_asset_id`,\\n  `page_number`,\\n  COALESCE(`text_ext`, `text_trx`) AS `text`\\nFROM (\\n  SELECT\\n    `items`.`id` AS `item_id`,\\n    `title` AS `item_title`,\\n    `collection_id`,\\n    `metadata`,\\n    `items`.`created_at` AS `item_created_at`,\\n    `items`.`updated_at` AS `item_updated_at`,\\n    `name` AS `collection_name`,\\n    `description` AS `collection_description`,\\n    `collections`.`created_at` AS `collection_created_at`,\\n    `collections`.`updated_at` AS `collection_updated_at`,\\n    `assets`.`id` AS `asset_id`,\\n    `path` AS `asset_path`,\\n    `type` AS `asset_type`,\\n    `size` AS `asset_size`,\\n    `assets`.`created_at` AS `asset_created_at`,\\n    `sort_index` AS `asset_sort_index`,\\n    `parent_asset_id`,\\n    `page_number`,\\n    `extractions`.`text_content` AS `text_ext`,\\n    `transcriptions`.`text_content` AS `text_trx`\\n  FROM `items`\\n  LEFT JOIN `collections`\\n    ON (`items`.`collection_id` = `collections`.`id`)\\n  LEFT JOIN `assets`\\n    ON (`items`.`id` = `assets`.`item_id`)\\n  LEFT JOIN `extractions`\\n    ON (`assets`.`id` = `extractions`.`asset_id`)\\n  LEFT JOIN `transcriptions`\\n    ON (`assets`.`id` = `transcriptions`.`asset_id`)\\n) AS `q01`\\nWHERE (`asset_type` = 'pdf')\\nORDER BY `item_id`, `asset_id`\","
```

## Exportar

CSV/TSV perezosos se *streamean*. JSON/RDS/parquet/arrow son archivo
completo. CSV se escribe en UTF-8 real.

``` r

csv_path <- tempfile(fileext = ".csv")
entropia_export(entropia_corpus(con), csv_path)
read.csv(csv_path) |> nrow()
#> [1] 5
```

``` r

rds_path <- tempfile(fileext = ".rds")
entropia_export(ds, rds_path, format = "rds")
back <- readRDS(rds_path)
class(back)
#> [1] "entropia_dataset" "tbl_df"           "tbl"              "data.frame"
```

## Flujo recomendado

Snapshot primero; la procedencia registra *ese* archivo:

``` r

snap <- tempfile(fileext = ".sqlite")
entropia_copy(con, snap)
snap_con <- entropia_connect(snap)
stable <- entropia_analysis_dataset(snap_con, name = "stable", asset_type == "pdf")
entropia_provenance(stable)[["source_path"]] == snap
#> [1] TRUE
entropia_disconnect(snap_con)
```

``` r

entropia_disconnect(con)
```

Siguiente:
[`vignette("analysis")`](https://humalab.github.io/EntropIA-R/articles/analysis.md).
English:
[`vignette("datasets.en")`](https://humalab.github.io/EntropIA-R/articles/datasets.en.md).
