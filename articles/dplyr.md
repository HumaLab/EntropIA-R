# Lazy queries with dplyr

## Everything is a lazy table

Every accessor returns a `tbl_sql` backed by SQLite. That means you can
compose the whole `dplyr` grammar — `filter`, `select`, `mutate`,
`arrange`, `group_by`, `summarise`, `left_join` — and the *entire query*
is translated to SQL and executed by SQLite. Nothing is loaded into R
until you `collect()`.

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

The `entropiaR` package deliberately defines *no* custom verbs. `dplyr`
works because the accessors are plain `tbl_sql` — zero magic, and you
can read dbplyr documentation for the full verb vocabulary.

## Filters and selection push down

This never pulls the `items` table into memory:

``` r

q <- entropia_items(con) |>
  filter(grepl("huelga", title, ignore.case = TRUE)) |>
  select(id, title, created_at)
```

You can inspect the generated SQL to confirm the work stays on SQLite:

``` r

dbplyr::sql_render(q)
#> Warning: Named arguments ignored for SQL grepl
#> <SQL> SELECT `id`, `title`, `created_at`
#> FROM `items`
#> WHERE (grepl('huelga', `title`, 1 AS `ignore.case`))
```

tidyselect works natively too — the `select()` above could have been
written with helpers like `starts_with()`:

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

## Joins across accessors

Because every accessor is a `tbl_sql`, you can join them directly.
Entities join to items for context:

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

Note that
[`entropia_entities()`](https://humalab.github.io/EntropIA-R/reference/entropia_entities.md)
excludes soft-deleted rows by default (`source = 'manual_deleted'`), and
`min_confidence` filters on confidence — both push down to SQL.

## Grouped summaries

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

## Parameter-safe full-text search

[`entropia_search()`](https://humalab.github.io/EntropIA-R/reference/entropia_search.md)
wraps SQLite’s FTS5 index and is injection-safe: your query text is
escaped via `dbQuoteString` before it is spliced into `MATCH`. Results
come back ranked by BM25.

``` r

entropia_search(con, "huelga") |> collect()
#> # A tibble: 2 × 8
#>   id     title collection_id metadata created_at updated_at search_text     rank
#>   <chr>  <chr> <chr>         <chr>       <int64>    <int64> <chr>          <dbl>
#> 1 22222… Mani… 11111111-111… "{\"__e…      1.e12      1.e12 "Manifiest… -1.10e-6
#> 2 22222… Cart… 11111111-111… "{\"__e…      1.e12      1.e12 "Carta al … -1.01e-6
```

`index = "chunks"` searches the RAG chunk index instead:

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

Multi-word queries are AND-ed, `limit` truncates the ranked result, and
the query itself is never interpolated into SQL.

## Collecting applies the column contract

[`entropia_collect()`](https://humalab.github.io/EntropIA-R/reference/entropia_collect.md)
is `collect()` plus the package’s column contract: millisecond
timestamps become `POSIXct`, JSON-in-TEXT columns become list-columns,
and embedding BLOBs stay `raw` (and are not selected unless you opt in).

``` r

items <- entropia_items(con) |> entropia_collect()
items$created_at
#> [1] "2026-01-15 12:01:00 UTC" "2026-01-15 12:03:00 UTC"
#> [3] "2026-01-15 12:05:00 UTC"
```

``` r

metadata_col <- entropia_items(con) |> entropia_collect()
metadata_col$metadata
#> [[1]]
#> [[1]]$`__entropia_file_metadata`
#> [[1]]$`__entropia_file_metadata`$original_name
#> [1] "manifiesto.pdf"
#> 
#> [[1]]$`__entropia_file_metadata`$original_path
#> [1] "/docs/manifiesto.pdf"
#> 
#> [[1]]$`__entropia_file_metadata`$importedAt
#> [1] "2026-01-15T12:05:00Z"
#> 
#> 
#> [[1]]$page_count
#> [1] 2
#> 
#> 
#> [[2]]
#> [[2]]$`__entropia_file_metadata`
#> [[2]]$`__entropia_file_metadata`$original_name
#> [1] "carta.mp3"
#> 
#> [[2]]$`__entropia_file_metadata`$original_path
#> [1] "/docs/carta.mp3"
#> 
#> [[2]]$`__entropia_file_metadata`$importedAt
#> [1] "2026-01-15T12:06:00Z"
#> 
#> 
#> 
#> [[3]]
#> [1] NA
```

The pure timestamp helpers back this:
[`entropia_datetime()`](https://humalab.github.io/EntropIA-R/reference/entropia_datetime.md)
converts milliseconds,
[`entropia_datetime_s()`](https://humalab.github.io/EntropIA-R/reference/entropia_datetime_s.md)
seconds, and
[`entropia_datetime_auto()`](https://humalab.github.io/EntropIA-R/reference/entropia_datetime_auto.md)
uses a magnitude guard for columns whose units have drifted over time
(used for `entities.created_at` and `triples.created_at`):

``` r

entropia_datetime(1768478400000)
#> [1] "2026-01-15 12:00:00 UTC"
entropia_datetime_s(1768478400)
#> [1] "2026-01-15 12:00:00 UTC"
entropia_datetime_auto(c(1768478400000, 1768478400))
#> [1] "2026-01-15 12:00:00 UTC" "2026-01-15 12:00:00 UTC"
```

## Cleaning up

``` r

entropia_disconnect(con)
```

Next:
[`vignette("datasets")`](https://humalab.github.io/EntropIA-R/articles/datasets.md)
for building reproducible analysis datasets, or
[`vignette("analysis")`](https://humalab.github.io/EntropIA-R/articles/analysis.md)
for a complete analysis workflow.
