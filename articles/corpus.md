# Exploring the corpus

## The domain model

EntropIA organizes your research material in a three-level hierarchy:

    collections ──→ items ──→ assets

- a **collection** is a research project or folder (e.g. “Conflicto SOIP
  1965-66”);
- an **item** is one document inside a collection (a newspaper page, a
  letter, a photo);
- an **asset** is one physical file belonging to an item — an image, a
  PDF, or an audio recording. A PDF item usually has one asset *per
  page*; PDF page assets point at their parent asset via
  `parent_asset_id` and carry a `page_number`.

Everything else hangs off this spine: text layers (`extractions`,
`transcriptions`, `layouts`), entities and triples, notes and
annotations, topics, LLM results, and RAG artifacts.

## Accessors are lazy

Every accessor returns a lazy `tbl_sql` — a query that has *not* run
yet. SQLite does the work when you collect. Nothing is loaded into R
memory until you ask:

``` r

con <- entropia_connect(system.file("extdata", "entropia-example.sqlite", package = "entropiaR"))
items <- entropia_items(con)
items
#> # A query:  ?? x 7
#> # Database: sqlite 3.53.3 [/home/runner/work/_temp/Library/entropiaR/extdata/entropia-example.sqlite]
#>   id              title collection_id metadata created_at updated_at search_text
#>   <chr>           <chr> <chr>         <chr>       <int64>    <int64> <chr>      
#> 1 22222222-2222-… Mani… 11111111-111… "{\"__e…      1.e12      1.e12 "Manifiest…
#> 2 22222222-2222-… Cart… 11111111-111… "{\"__e…      1.e12      1.e12 "Carta al …
#> 3 22222222-2222-… Foto… 11111111-111…  NA           1.e12      1.e12 "Fotografí…
```

Because these are `tbl_sql`, you can pipe them straight into dplyr verbs
and the whole query is translated to SQL (see
[`vignette("dplyr")`](https://github.com/HumaLab/EntropIA-R/articles/dplyr.md)).

## The three spine accessors

``` r

entropia_collections(con) |> collect()
#> # A tibble: 1 × 5
#>   id                                   name    description created_at updated_at
#>   <chr>                                <chr>   <chr>          <int64>    <int64>
#> 1 11111111-1111-4111-8111-111111111111 Archiv… Colección …      1.e12      1.e12
```

``` r

entropia_items(con) |> collect()
#> # A tibble: 3 × 7
#>   id              title collection_id metadata created_at updated_at search_text
#>   <chr>           <chr> <chr>         <chr>       <int64>    <int64> <chr>      
#> 1 22222222-2222-… Mani… 11111111-111… "{\"__e…      1.e12      1.e12 "Manifiest…
#> 2 22222222-2222-… Cart… 11111111-111… "{\"__e…      1.e12      1.e12 "Carta al …
#> 3 22222222-2222-… Foto… 11111111-111…  NA           1.e12      1.e12 "Fotografí…
```

``` r

entropia_assets(con) |> collect()
#> # A tibble: 5 × 9
#>   id             item_id path  type   size created_at sort_index parent_asset_id
#>   <chr>          <chr>   <chr> <chr> <int>    <int64>      <int> <chr>          
#> 1 33333333-3333… 222222… stor… pdf   20480      1.e12          0 NA             
#> 2 33333333-3333… 222222… stor… pdf   10240      1.e12          1 33333333-3333-…
#> 3 33333333-3333… 222222… stor… pdf   10240      1.e12          2 33333333-3333-…
#> 4 33333333-3333… 222222… stor… image  5120      1.e12          0 NA             
#> 5 33333333-3333… 222222… stor… audio 40960      1.e12          0 NA             
#> # ℹ 1 more variable: page_number <int>
```

Notice the PDF pages: assets `...3332` and `...3333` carry a
`parent_asset_id` and a `page_number`, while the top-level PDF asset
does not. You can join pages back to their parent:

``` r

assets <- entropia_assets(con) |> collect()
assets |>
  filter(!is.na(page_number)) |>
  select(asset_id = id, page_number, parent_asset_id) |>
  left_join(select(assets, id, type), by = c("parent_asset_id" = "id"))
#> # A tibble: 2 × 4
#>   asset_id                             page_number parent_asset_id         type 
#>   <chr>                                      <int> <chr>                   <chr>
#> 1 33333333-3333-4333-8333-333333333332           1 33333333-3333-4333-833… pdf  
#> 2 33333333-3333-4333-8333-333333333333           2 33333333-3333-4333-833… pdf
```

The asset accessor never selects BLOB columns such as `embedding` —
those are opt-in (see
[`entropia_embeddings()`](https://github.com/HumaLab/EntropIA-R/reference/entropia_embeddings.md)
/
[`entropia_chunks()`](https://github.com/HumaLab/EntropIA-R/reference/entropia_chunks.md)).

## The corpus view

[`entropia_corpus()`](https://github.com/HumaLab/EntropIA-R/reference/entropia_corpus.md)
is the workhorse: it joins items, collections and assets in one lazy
query, one row per asset, and appends the best available text per asset:

``` r

corpus <- entropia_corpus(con)
corpus |> colnames()
#>  [1] "item_id"                "item_title"             "collection_id"         
#>  [4] "metadata"               "item_created_at"        "item_updated_at"       
#>  [7] "collection_name"        "collection_description" "collection_created_at" 
#> [10] "collection_updated_at"  "asset_id"               "asset_path"            
#> [13] "asset_type"             "asset_size"             "asset_created_at"      
#> [16] "asset_sort_index"       "parent_asset_id"        "page_number"           
#> [19] "text"
```

``` r

corpus |>
  select(item_title, asset_type, page_number, text) |>
  collect()
#> # A tibble: 5 × 4
#>   item_title              asset_type page_number text                           
#>   <chr>                   <chr>            <int> <chr>                          
#> 1 Manifiesto de la huelga pdf                 NA ![](page=1,bbox=[10,10,500,700…
#> 2 Manifiesto de la huelga pdf                  1 Segunda pagina del manifiesto …
#> 3 Manifiesto de la huelga pdf                  2 NA                             
#> 4 Carta al sindicato      audio               NA Compañeros, a la huelga        
#> 5 Fotografía de la marcha image               NA NA
```

Assets with no text layer keep their row and get `NA` text — no rows are
lost.

### Filtering

`collections` and `asset_types` accept character vectors and push the
filter down to SQL:

``` r

entropia_corpus(con, asset_types = "pdf") |>
  collect() |>
  nrow()
#> [1] 3
entropia_corpus(con, collections = "Archivo de prueba") |>
  collect() |>
  nrow()
#> [1] 5
```

By default the corpus includes PDF *page* assets. Set
`page_assets = FALSE` to see only top-level assets:

``` r

entropia_corpus(con) |>
  collect() |>
  nrow()
#> [1] 5
entropia_corpus(con, page_assets = FALSE) |>
  collect() |>
  nrow()
#> [1] 3
```

`include_deleted` is reserved for the v2 read-write release; in v1 the
flag has no effect (the corpus carries no soft-delete marker).

## Item metadata

[`entropia_metadata()`](https://github.com/HumaLab/EntropIA-R/reference/entropia_metadata.md)
parses the JSON inside `items.metadata` into tidy rows: the
`__entropia_file_metadata` fields become proper columns
(`original_name`, `original_path`, `imported_at` as a `POSIXct`), and
any remaining top-level keys become list-columns. Items without metadata
get a row with `NA`s rather than disappearing:

``` r

entropia_metadata(con)
#> # A tibble: 3 × 5
#>   item_id             original_name original_path imported_at         page_count
#>   <chr>               <chr>         <chr>         <dttm>              <list>    
#> 1 22222222-2222-4222… manifiesto.p… /docs/manifi… 2026-01-15 12:05:00 <int [1]> 
#> 2 22222222-2222-4222… carta.mp3     /docs/carta.… 2026-01-15 12:06:00 <NULL>    
#> 3 22222222-2222-4222… NA            NA            NA                  <NULL>
```

Pass `parse = FALSE` to see the raw JSON text instead.

## Cleaning up

``` r

entropia_disconnect(con)
```

Next:
[`vignette("text")`](https://github.com/HumaLab/EntropIA-R/articles/text.md)
for text extraction and metadata, or
[`vignette("dplyr")`](https://github.com/HumaLab/EntropIA-R/articles/dplyr.md)
for composing lazy queries.
