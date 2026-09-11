# Exploratory analysis of an EntropIA corpus

Start with a snapshot, then one shared overview. Do not collect the full
corpus until a table of counts tells you the universe is the one you
want.

``` r

con <- entropia_connect(system.file(
  "extdata", "entropia-example.sqlite",
  package = "entropiaR"
))
```

## Inventory without loading text

[`entropia_overview()`](https://humalab.github.io/EntropIA-R/reference/entropia_overview.md)
aggregates in SQLite. It never materialises OCR text, JSON metadata or
embedding BLOBs.

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

`counts` uses explicit units (`item`, `asset`, `collection`). `n` in
`collections` is the number of *rows in the study query* (assets plus
items without an asset), not a synonym for `n_items`.

## One universe, many tables

Every table in `eda` uses the same selection. Filter by asset type or
drop PDF page assets without rewriting joins:

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

An empty ID vector selects nothing (it does not fall back to “all”):

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

## Quality: numerators, denominators, status

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

Read `status` before `pct`:

- `ok` — the rate is defined;
- `empty` — eligible rows exist but the field/layer is empty;
- `no_data` — no rows in the denominator;
- `not_applicable` — the metric does not apply to that group (e.g. OCR
  on audio, depending on eligibility);
- `invalid` — JSON that does not parse.

`metadata_coverage` is *presence* of metadata text. `metadata_validity`
is JSON syntax, not “the document has an author and a date”.

## Entities and topics: occurrence vs prevalence

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

`n` is the number of rows (mentions). `n_items` is distinct items. `pct`
is `n_items / total` where `total` is the number of items in the
universe — items with no entity still sit in the denominator.

Soft-deleted entities (`source = "manual_deleted"`) stay out unless you
pass that source explicitly.

## Temporal profile and exclusions

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

Buckets are UTC month starts of the chosen `date_var` (default
`item_created_at`). That column is an *operational* timestamp (created /
imported), not necessarily the date of the historical document.

## Profile a collected tibble

Overview stays on SQL. Local distributions need a collected table:

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

[`entropia_profile()`](https://humalab.github.io/EntropIA-R/reference/entropia_profile.md)
returns `structure`, `missing`, `numeric`, `categorical`, `duplicates`
and `sampling`. Numeric ID columns are described but not treated as
scientific measurements in correlation plots (see
[`vignette("visualize")`](https://humalab.github.io/EntropIA-R/articles/visualize.md)).

Sampling is opt-in and does not change `.Random.seed`:

``` r

set.seed(1)
before <- .Random.seed
entropia_profile(lengths, sample_n = 2, seed = 99)$sampling$n
#> [1] 2
identical(.Random.seed, before)
#> [1] TRUE
```

## Hand-off

The same `eda` object feeds ggplot helpers, the Shiny dashboard and
[`entropia_report()`](https://humalab.github.io/EntropIA-R/reference/entropia_report.md)
— do not recompute a different filter per panel.

``` r

entropia_disconnect(con)
```

Next:
[`vignette("visualize")`](https://humalab.github.io/EntropIA-R/articles/visualize.md),
or
[`vignette("analysis")`](https://humalab.github.io/EntropIA-R/articles/analysis.md)
for a full snapshot → dataset → export loop.
