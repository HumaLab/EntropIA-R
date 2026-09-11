# Reproducible analysis datasets

*English version.* Spanish:
[`vignette("datasets")`](https://humalab.github.io/EntropIA-R/articles/datasets.md).

## Why provenance?

A research corpus changes over time: EntropIA keeps syncing, the schema
evolves, and a “just filter and collect” workflow makes it impossible to
say later *which* data produced a result. `entropiaR` solves this at the
boundary where a query becomes a dataset:
[`entropia_analysis_dataset()`](https://humalab.github.io/EntropIA-R/reference/entropia_analysis_dataset.md)
records exactly what went in.

``` r

con <- entropia_connect(system.file("extdata", "entropia-example.sqlite", package = "entropiaR"))
```

## Building a dataset

[`entropia_analysis_dataset()`](https://humalab.github.io/EntropIA-R/reference/entropia_analysis_dataset.md)
takes a connection, applies filter expressions to the corpus, collects
it, and stamps provenance:

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

The result is a tibble with class `entropia_dataset`, plus an
`entropia_prov` attribute (version 2 sidecar) recording the schema
version, the schema hash, the source-file snapshot digest, a canonical
digest of the collected rows, the resolved SQL, the selection recipe,
the source path, the filter labels, the package version, a build
timestamp, and the R version.

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
#>   built at:       2026-09-11T18:07:56.029Z
#>   R version:      R version 4.6.1 (2026-06-24)
```

Multiple filters compose, and they push down to SQL before the collect.
`unit = "item"` collapses to one row per document; `text = FALSE` skips
OCR:

``` r

entropia_analysis_dataset(con, name = "audio_items", asset_type == "audio") |>
  nrow()
#> [1] 1
entropia_analysis_dataset(con, unit = "item", text = FALSE, name = "items_only") |>
  ncol()
#> [1] 9
```

## Determinism

Identical inputs produce identical datasets. Rows are arranged on a
stable item/asset key before collecting, so row order never depends on
the physical layout of the database:

``` r

a <- entropia_analysis_dataset(con, asset_type == "image")
b <- entropia_analysis_dataset(con, asset_type == "image")
identical(as.data.frame(a), as.data.frame(b)) # data bytes identical
#> [1] FALSE
identical(
  entropia_provenance(a)[["dataset_sha256"]],
  entropia_provenance(b)[["dataset_sha256"]]
)
#> [1] TRUE
```

Only `built_at` differs between builds. Structural identity
(`schema_hash`) and data identity (`dataset_sha256`) are separate
claims: an UPDATE that changes rows leaves `schema_hash` intact but
changes the data digest, and reading
[`entropia_provenance()`](https://humalab.github.io/EntropIA-R/reference/entropia_provenance.md)
on a *derived* object re-computes the current digest, marks
`scope = "derived"`, and keeps the origin digest and SQL under `origin`
instead of claiming the original query reproduces transformed rows.

## Provenance sidecars

[`entropia_write_provenance()`](https://humalab.github.io/EntropIA-R/reference/entropia_write_provenance.md)
writes the provenance as a JSON sidecar, so a dataset and its
`-prov.json` file travel together and survive email, archives, and other
people’s machines:

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

## Exporting

[`entropia_export()`](https://humalab.github.io/EntropIA-R/reference/entropia_export.md)
writes a dataset or a lazy query to disk. Delimited formats (csv/tsv)
are *streamed* for lazy inputs — they fetch in chunks and never collect
the whole result — and the output is deterministically ordered. JSON,
RDS, parquet and arrow are whole-file formats.

``` r

csv_path <- tempfile(fileext = ".csv")
entropia_export(entropia_corpus(con), csv_path) # lazy input, streamed
read.csv(csv_path) |> nrow()
#> [1] 5
```

``` r

rds_path <- tempfile(fileext = ".rds")
entropia_export(ds, rds_path, format = "rds") # class + provenance intact
back <- readRDS(rds_path)
class(back)
#> [1] "entropia_dataset" "tbl_df"           "tbl"              "data.frame"
```

``` r

json_path <- tempfile(fileext = ".json")
entropia_export(entropia_collect(entropia_corpus(con)), json_path, format = "json")
jsonlite::fromJSON(json_path) |> nrow()
#> [1] 5
```

parquet/arrow are available when the `arrow` package is installed (it is
a Suggests dependency, so `entropia_export` fails with clear guidance
rather than a load error when it is not).

## Recommended workflow

For anything that will take a while, snapshot the database first, then
build datasets against the snapshot. The provenance then records the
*snapshot* as the source, so the analysis is immune to writes landing in
the meantime:

``` r

snap <- tempfile(fileext = ".sqlite")
entropia_copy(con, snap)
snap_con <- entropia_connect(snap)
stable <- entropia_analysis_dataset(snap_con, name = "stable", asset_type == "pdf")
entropia_provenance(stable)[["source_path"]] == snap
#> [1] TRUE
entropia_disconnect(snap_con)
```

## Cleaning up

``` r

entropia_disconnect(con)
```

Next:
[`vignette("analysis")`](https://humalab.github.io/EntropIA-R/articles/analysis.md)
for a complete end-to-end analysis, or
[`vignette("administration")`](https://humalab.github.io/EntropIA-R/articles/administration.md)
for the safety model around the database.
