# Write a provenance sidecar (JSON)

Persists the provenance stamp of a reproducible dataset as a JSON file,
the sidecar that travels with the analysis output. `NULL` values are
written as JSON `null` and `NA` values as `null`, so the file
round-trips through
[`jsonlite::fromJSON()`](https://jeroen.r-universe.dev/jsonlite/reference/fromJSON.html)
back to the same structure (apart from the list class). The file is
UTF-8.

## Usage

``` r
entropia_write_provenance(x, path)
```

## Arguments

- x:

  An object carrying a provenance stamp (see
  [`entropia_provenance()`](https://humalab.github.io/EntropIA-R/reference/entropia_provenance.md)).

- path:

  Destination file path. Must be a single path.

## Value

The normalized `path`, invisibly.

## Examples

``` r
con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
  package = "entropiaR"
))
ds <- entropia_analysis_dataset(con, asset_type == "image")
path <- tempfile(fileext = ".json")
entropia_write_provenance(ds, path)
readLines(path)
#>  [1] "{"                                                                                                
#>  [2] "  \"name\": null,"                                                                                
#>  [3] "  \"schema_version\": \"0029_rag_chunks\","                                                       
#>  [4] "  \"content_hash\": \"09d4c603b66d68c4c0cef0f51ff09a04fb30a49fe200907ef69693d11dd25732\","        
#>  [5] "  \"source_path\": \"/home/runner/work/_temp/Library/entropiaR/extdata/entropia-example.sqlite\","
#>  [6] "  \"filters\": \"asset_type == \\\"image\\\"\","                                                  
#>  [7] "  \"package_version\": \"0.0.0.9000\","                                                           
#>  [8] "  \"built_at\": \"2026-08-24T01:10:22.455Z\","                                                    
#>  [9] "  \"r_version\": \"R version 4.6.1 (2026-06-24)\""                                                
#> [10] "}"                                                                                                
entropia_disconnect(con)
```
