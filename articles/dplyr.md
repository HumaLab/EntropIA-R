# Consultas perezosas con dplyr

*Versión en español.* English:
[`vignette("dplyr.en")`](https://humalab.github.io/EntropIA-R/articles/dplyr.en.md).

## Todo es una tabla perezosa

Cada accesor es un `tbl_sql`. Podés componer `filter`, `select`,
`mutate`, `arrange`, `group_by`, `summarise`, `left_join` y **toda** la
consulta se traduce a SQL. Nada entra a R hasta
[`collect()`](https://dplyr.tidyverse.org/reference/compute.html) /
[`entropia_collect()`](https://humalab.github.io/EntropIA-R/reference/entropia_collect.md).

``` r

con <- entropia_connect(system.file("extdata", "entropia-example.sqlite", package = "entropiaR"))

entropia_items(con) |>
  filter(collection_id == "11111111-1111-4111-8111-111111111111") |>
  select(id, title) |>
  collect()
#> # A tibble: 3 × 2
#>   id                                   title                  
#>   <chr>                                <chr>                  
#> 1 22222222-2222-4222-8222-222222222221 Manifiesto de la huelga
#> 2 22222222-2222-4222-8222-222222222222 Carta al sindicato     
#> 3 22222222-2222-4222-8222-222222222223 Fotografía de la marcha
```

El paquete no define verbos propios. dplyr funciona porque los accesores
son `tbl_sql` planos.

## Los filtros bajan a SQLite

Esto no baja la tabla `items` a memoria:

``` r

q <- entropia_items(con) |>
  filter(grepl("huelga", title, ignore.case = TRUE)) |>
  select(id, title, created_at)
```

``` r

dbplyr::sql_render(q)
#> Warning: Named arguments ignored for SQL grepl
#> <SQL> SELECT `id`, `title`, `created_at`
#> FROM `items`
#> WHERE (grepl('huelga', `title`, 1 AS `ignore.case`))
```

``` r

entropia_items(con) |>
  select(id, starts_with("created")) |>
  collect()
#> # A tibble: 3 × 2
#>   id                                      created_at
#>   <chr>                                      <int64>
#> 1 22222222-2222-4222-8222-222222222221 1768478460000
#> 2 22222222-2222-4222-8222-222222222222 1768478580000
#> 3 22222222-2222-4222-8222-222222222223 1768478700000
```

## Joins entre accesores

``` r

entropia_entities(con) |>
  left_join(entropia_items(con), by = c("item_id" = "id")) |>
  select(entity_type, value, title) |>
  collect()
#> # A tibble: 3 × 3
#>   entity_type  value                 title                  
#>   <chr>        <chr>                 <chr>                  
#> 1 person       Juan Pérez            Manifiesto de la huelga
#> 2 place        Plaza de Mayo         Manifiesto de la huelga
#> 3 organization Sindicato Ferroviario Carta al sindicato
```

[`entropia_entities()`](https://humalab.github.io/EntropIA-R/reference/entropia_entities.md)
excluye borrados lógicos (`source = 'manual_deleted'`) salvo que pidas
lo contrario.

## Resúmenes agrupados

``` r

entropia_assets(con) |>
  group_by(type) |>
  summarise(n = n(), total_size = sum(size, na.rm = TRUE)) |>
  arrange(desc(n)) |>
  collect()
#> # A tibble: 3 × 3
#>   type      n total_size
#>   <chr> <int>      <int>
#> 1 pdf       3      40960
#> 2 image     1       5120
#> 3 audio     1      40960
```

## Búsqueda full-text segura

[`entropia_search()`](https://humalab.github.io/EntropIA-R/reference/entropia_search.md)
usa FTS5; el texto se escapa con `dbQuoteString`. Ranking BM25.

``` r

entropia_search(con, "huelga") |> collect()
#> # A tibble: 2 × 8
#>   id     title collection_id metadata created_at updated_at search_text     rank
#>   <chr>  <chr> <chr>         <chr>       <int64>    <int64> <chr>          <dbl>
#> 1 22222… Mani… 11111111-111… "{\"__e…      1.e12      1.e12 "Manifiest… -1.10e-6
#> 2 22222… Cart… 11111111-111… "{\"__e…      1.e12      1.e12 "Carta al … -1.01e-6
```

``` r

entropia_search(con, "huelga", index = "chunks") |> collect()
#> # A tibble: 1 × 15
#>   id           asset_id item_id source_kind source_id chunk_ordinal text_content
#>   <chr>        <chr>    <chr>   <chr>       <chr>             <int> <chr>       
#> 1 ragchk-0000… 3333333… 222222… extraction  ext-3333…             0 La huelga g…
#> # ℹ 8 more variables: start_char <int>, end_char <int>, source_text_hash <chr>,
#> #   chunking_contract <chr>, embedding_model <chr>, embedding_contract <chr>,
#> #   dimensions <int>, rank <dbl>
```

## Collect aplica el contrato

Timestamps en ms → `POSIXct`; JSON → list-columns.

``` r

items <- entropia_items(con) |> entropia_collect()
items$created_at
#> [1] "2026-01-15 12:01:00 UTC" "2026-01-15 12:03:00 UTC"
#> [3] "2026-01-15 12:05:00 UTC"
```

`rename` conserva el tipo de la columna **origen**. Una expresión nueva
que reutiliza el nombre de un timestamp **no** se convierte:

``` r

class(entropia_collect(rename(entropia_items(con), imported = created_at))$imported)
#> [1] "POSIXct" "POSIXt"
class(entropia_collect(mutate(entropia_items(con), created_at = 1))$created_at)
#> [1] "numeric"
```

Los joins no tienen contrato automático: pasá `schema =` (ver
[`?entropia_collect`](https://humalab.github.io/EntropIA-R/reference/entropia_collect.md)).

``` r

entropia_datetime(1768478400000)
#> [1] "2026-01-15 12:00:00 UTC"
entropia_datetime_s(1768478400)
#> [1] "2026-01-15 12:00:00 UTC"
entropia_datetime_auto(c(1768478400000, 1768478400))
#> [1] "2026-01-15 12:00:00 UTC" "2026-01-15 12:00:00 UTC"
```

``` r

entropia_disconnect(con)
```

Siguiente:
[`vignette("eda")`](https://humalab.github.io/EntropIA-R/articles/eda.md).
English:
[`vignette("dplyr.en")`](https://humalab.github.io/EntropIA-R/articles/dplyr.en.md).
