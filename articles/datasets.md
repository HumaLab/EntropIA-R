# Reproducible analysis datasets

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
ds
#> entropia_dataset: pdf_documents
#>   schema: 0029_rag_chunks  content: 09d4c603b66d
#>   filters: asset_type == "pdf"
#> # A tibble: 3 × 19
#>   item_id      item_title collection_id metadata item_created_at item_updated_at
#>   <chr>        <chr>      <chr>         <chr>            <int64>         <int64>
#> 1 22222222-22… Manifiest… 11111111-111… "{\"__e…   1768478460000   1768478520000
#> 2 22222222-22… Manifiest… 11111111-111… "{\"__e…   1768478460000   1768478520000
#> 3 22222222-22… Manifiest… 11111111-111… "{\"__e…   1768478460000   1768478520000
#> # ℹ 13 more variables: collection_name <chr>, collection_description <chr>,
#> #   collection_created_at <int64>, collection_updated_at <int64>,
#> #   asset_id <chr>, asset_path <chr>, asset_type <chr>, asset_size <int>,
#> #   asset_created_at <int64>, asset_sort_index <int>, parent_asset_id <chr>,
#> #   page_number <int>, text <chr>
```

The result is a tibble with class `entropia_dataset`, plus an
`entropia_prov` attribute recording the schema version, the content hash
of the source schema, the source path, the filter expressions, the
package version, a build timestamp, and the R version.

``` r

entropia_provenance(ds)
#> entropiaR dataset provenance
#>   name:           pdf_documents
#>   schema version: 0029_rag_chunks
#>   content hash:   09d4c603b66d68c4c0cef0f51ff09a04fb30a49fe200907ef69693d11dd25732
#>   source path:    /home/runner/work/_temp/Library/entropiaR/extdata/entropia-example.sqlite
#>   filters:        asset_type == "pdf"
#>   package:        0.0.0.9000
#>   built at:       2026-08-24T01:10:41.621Z
#>   R version:      R version 4.6.1 (2026-06-24)
```

Multiple filters compose, and they push down to SQL before the collect:

``` r

entropia_analysis_dataset(con, name = "audio_items", asset_type == "audio") |>
  nrow()
#> [1] 1
```

## Determinism

Identical inputs produce identical datasets. The corpus is always
arranged on `asset_id` before collecting, so row order never depends on
the physical layout of the database:

``` r

a <- entropia_analysis_dataset(con, asset_type == "image")
b <- entropia_analysis_dataset(con, asset_type == "image")
identical(a, b) # data bytes identical
#> [1] FALSE
identical(
  entropia_provenance(a)[["content_hash"]],
  entropia_provenance(b)[["content_hash"]]
)
#> [1] TRUE
```

Only `built_at` differs between builds.

## Provenance sidecars

[`entropia_write_provenance()`](https://humalab.github.io/EntropIA-R/reference/entropia_write_provenance.md)
writes the provenance as a JSON sidecar, so a dataset and its
`-prov.json` file travel together and survive email, archives, and other
people’s machines:

``` r

prov_path <- tempfile(fileext = "-prov.json")
entropia_write_provenance(ds, prov_path)
readLines(prov_path)[1:9]
#> [1] "{"                                                                                                
#> [2] "  \"name\": \"pdf_documents\","                                                                   
#> [3] "  \"schema_version\": \"0029_rag_chunks\","                                                       
#> [4] "  \"content_hash\": \"09d4c603b66d68c4c0cef0f51ff09a04fb30a49fe200907ef69693d11dd25732\","        
#> [5] "  \"source_path\": \"/home/runner/work/_temp/Library/entropiaR/extdata/entropia-example.sqlite\","
#> [6] "  \"filters\": \"asset_type == \\\"pdf\\\"\","                                                    
#> [7] "  \"package_version\": \"0.0.0.9000\","                                                           
#> [8] "  \"built_at\": \"2026-08-24T01:10:41.621Z\","                                                    
#> [9] "  \"r_version\": \"R version 4.6.1 (2026-06-24)\""
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
