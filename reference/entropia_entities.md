# Entities (lazy)

A lazy [`dplyr::tbl()`](https://dplyr.tidyverse.org/reference/tbl.html)
over the `entities` table (named-entity recognition output). Two filters
are applied, both pushed down to SQL:

## Usage

``` r
entropia_entities(con, include_deleted = FALSE, min_confidence = NULL)
```

## Arguments

- con:

  A connection returned by
  [`entropia_connect()`](https://github.com/HumaLab/EntropIA-R/reference/entropia_connect.md).

- include_deleted:

  Include soft-deleted entities (`source = "manual_deleted"`). Default
  `FALSE`.

- min_confidence:

  Optional numeric threshold in `[0, 1]`; rows with
  `confidence < min_confidence` are excluded. `NULL` (default) keeps all
  confidence levels.

## Value

A `tbl_sql` on `entities`.

## Details

- By default rows marked soft-deleted (`source = "manual_deleted"`, the
  app's hidden marker) are excluded; pass `include_deleted = TRUE` to
  keep them. On schemas that predate the `source` column
  (migration 0009) there is no marker to honour and the filter is a
  no-op.

- Set `min_confidence` to keep only entities at or above a confidence
  threshold.

`created_at` uses the magnitude-guarded `datetime_auto` contract (the
app writes epoch milliseconds, the DDL default is seconds); `asset_id`
is NULL for item-level entities.

## Examples

``` r
con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
  package = "entropiaR"
))
entropia_collect(entropia_entities(con)) # soft-deleted rows excluded
#> # A tibble: 3 × 16
#>   id         item_id entity_type value start_offset end_offset confidence source
#>   <chr>      <chr>   <chr>       <chr>        <int>      <int>      <dbl> <chr> 
#> 1 77777777-… 222222… person      Juan…            0         10       0.97 ner   
#> 2 77777777-… 222222… place       Plaz…           12         24       0.93 ner   
#> 3 77777777-… 222222… organizati… Sind…            5         26       0.9  ner   
#> # ℹ 8 more variables: model_name <chr>, created_at <dttm>, latitude <dbl>,
#> #   longitude <dbl>, geo_status <chr>, asset_id <chr>, manual_lat <dbl>,
#> #   manual_lon <dbl>
entropia_collect(entropia_entities(con, include_deleted = TRUE))
#> # A tibble: 4 × 16
#>   id         item_id entity_type value start_offset end_offset confidence source
#>   <chr>      <chr>   <chr>       <chr>        <int>      <int>      <dbl> <chr> 
#> 1 77777777-… 222222… person      Juan…            0         10       0.97 ner   
#> 2 77777777-… 222222… place       Plaz…           12         24       0.93 ner   
#> 3 77777777-… 222222… organizati… Sind…            5         26       0.9  ner   
#> 4 77777777-… 222222… person      Pers…            0         14       0.5  manua…
#> # ℹ 8 more variables: model_name <chr>, created_at <dttm>, latitude <dbl>,
#> #   longitude <dbl>, geo_status <chr>, asset_id <chr>, manual_lat <dbl>,
#> #   manual_lon <dbl>
entropia_collect(entropia_entities(con, min_confidence = 0.9))
#> # A tibble: 3 × 16
#>   id         item_id entity_type value start_offset end_offset confidence source
#>   <chr>      <chr>   <chr>       <chr>        <int>      <int>      <dbl> <chr> 
#> 1 77777777-… 222222… person      Juan…            0         10       0.97 ner   
#> 2 77777777-… 222222… place       Plaz…           12         24       0.93 ner   
#> 3 77777777-… 222222… organizati… Sind…            5         26       0.9  ner   
#> # ℹ 8 more variables: model_name <chr>, created_at <dttm>, latitude <dbl>,
#> #   longitude <dbl>, geo_status <chr>, asset_id <chr>, manual_lat <dbl>,
#> #   manual_lon <dbl>
entropia_disconnect(con)
```
