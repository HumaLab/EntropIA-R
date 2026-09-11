# Explorar el corpus

*Versión en español.* English:
[`vignette("corpus.en")`](https://humalab.github.io/EntropIA-R/articles/corpus.en.md).

## El modelo de dominio

EntropIA organiza el material en tres niveles:

    collections ──→ items ──→ assets

- una **colección** es un proyecto o carpeta;
- un **ítem** es un documento dentro de la colección;
- un **asset** es un archivo físico (imagen, PDF o audio). Un PDF suele
  tener un asset *por página*, con `parent_asset_id` y `page_number`.

El resto cuelga de esa espina: capas de texto, entidades, notas, temas,
resultados de LLM y RAG.

## Los accesores son perezosos

Cada accesor devuelve un `tbl_sql`: la consulta **todavía no corrió**.
SQLite trabaja cuando colectás.

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

## Los tres accesores de la espina

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

Las páginas PDF llevan `parent_asset_id` y `page_number`. El accesor de
assets nunca selecciona BLOB (`embedding`): eso es opt-in
([`entropia_embeddings()`](https://humalab.github.io/EntropIA-R/reference/entropia_embeddings.md)
/
[`entropia_chunks()`](https://humalab.github.io/EntropIA-R/reference/entropia_chunks.md)).

## La vista corpus

[`entropia_corpus()`](https://humalab.github.io/EntropIA-R/reference/entropia_corpus.md)
une ítems, colecciones y assets. El grano es **una fila por asset
vinculado, más una fila por ítem sin asset** (`asset_id` entonces es
`NA`). Assets huérfanos y colecciones vacías no aparecen. Los timestamps
prefijados siguen enteros hasta un `schema` explícito en
[`entropia_collect()`](https://humalab.github.io/EntropIA-R/reference/entropia_collect.md):
el join no tiene contrato de una sola tabla.

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
  dplyr::select(item_title, asset_type, page_number, text) |>
  dplyr::collect()
#> # A tibble: 5 × 4
#>   item_title              asset_type page_number text                           
#>   <chr>                   <chr>            <int> <chr>                          
#> 1 Manifiesto de la huelga pdf                 NA ![](page=1,bbox=[10,10,500,700…
#> 2 Manifiesto de la huelga pdf                  1 Segunda pagina del manifiesto …
#> 3 Manifiesto de la huelga pdf                  2 NA                             
#> 4 Carta al sindicato      audio               NA Compañeros, a la huelga        
#> 5 Fotografía de la marcha image               NA NA
```

### Filtros

`collections` compara `collections.name`. Preferí `collection_ids` si
los nombres pueden repetirse (el nombre **no** es único):

``` r

entropia_corpus(con, asset_types = "pdf") |>
  dplyr::collect() |>
  nrow()
#> [1] 3
ids <- entropia_collections(con) |> dplyr::collect() |> dplyr::pull(id)
entropia_corpus(con, collection_ids = ids[1]) |>
  dplyr::collect() |>
  nrow()
#> [1] 5
```

Por defecto el corpus incluye páginas PDF. `page_assets = FALSE` deja
solo assets de primer nivel:

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

`include_deleted` está reservado para v2; en v1 no tiene efecto.

## Metadatos del ítem

[`entropia_metadata()`](https://humalab.github.io/EntropIA-R/reference/entropia_metadata.md)
parsea el JSON de `items.metadata`: campos de `__entropia_file_metadata`
a columnas (`original_name`, `original_path`, `imported_at` como
`POSIXct`). Ítems sin metadata quedan con `NA`, no desaparecen.

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

`parse = FALSE` devuelve el JSON crudo.

``` r

entropia_disconnect(con)
```

Siguiente:
[`vignette("text")`](https://humalab.github.io/EntropIA-R/articles/text.md).
English:
[`vignette("corpus.en")`](https://humalab.github.io/EntropIA-R/articles/corpus.en.md).
