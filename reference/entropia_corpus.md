# Corpus (lazy)

The workhorse research query: a lazy join of `items`, `collections` and
`assets`, one row per item-asset pair, plus one row with missing asset
fields for each item without assets, with an optional per-asset `text`
column. Asset-type filters remove missing-asset rows; excluding page
assets filters existing rows and does not create replacement rows for
page-only items. Nothing is fetched at access time; every join and
filter is pushed down to SQLite, and the result stays composable with
[`dplyr::filter()`](https://dplyr.tidyverse.org/reference/filter.html),
[`dplyr::select()`](https://dplyr.tidyverse.org/reference/select.html)
and friends.

## Usage

``` r
entropia_corpus(
  con,
  collections = NULL,
  asset_types = NULL,
  text = "auto",
  page_assets = TRUE,
  include_deleted = FALSE,
  collection_ids = NULL,
  item_ids = NULL
)
```

## Arguments

- con:

  A connection returned by
  [`entropia_connect()`](https://humalab.github.io/EntropIA-R/reference/entropia_connect.md).

- collections:

  Optional character vector of collection names to keep (matches
  `collections.name`). `NULL` (default) keeps all collections.

- asset_types:

  Optional character vector of asset types to keep (matches
  `assets.type`, e.g. `image`, `pdf`, `audio`). `NULL` (default) keeps
  all.

- text:

  The text layer to append: `"auto"` (default), `"extraction"`,
  `"transcription"`, or `FALSE` to omit the `text` column.

- page_assets:

  When `TRUE` (default) every asset is kept; when `FALSE` PDF page
  assets (rows with a `parent_asset_id`) are excluded. A no-op on
  schemas without the page columns (migration 0024).

- include_deleted:

  Reserved. The corpus tables carry no soft-delete marker in the
  reference schema, so the flag currently has no effect; it is validated
  and kept for API symmetry with
  [`entropia_entities()`](https://humalab.github.io/EntropIA-R/reference/entropia_entities.md)
  and for forward compatibility with schemas that introduce one.

- collection_ids:

  Optional character vector of collection IDs. Applied together with the
  legacy collection-name filter (intersection).

- item_ids:

  Optional character vector of item IDs. For either ID filter, `NULL`
  means unrestricted and
  [`character()`](https://rdrr.io/r/base/character.html) selects zero
  rows.

## Value

A plain `tbl_sql` at item-asset grain, retaining items without assets as
missing-asset rows unless removed by filters, with prefixed columns from
`items`, `collections` and `assets`, plus `text` unless `text = FALSE`.

## Details

Column names are unambiguous across the three joined tables (e.g.
`item_id`, `asset_id`, `collection_name`, `item_created_at`,
`asset_created_at`), so there are no name collisions. `metadata` is the
raw JSON text of `items.metadata`; use
[`entropia_metadata()`](https://humalab.github.io/EntropIA-R/reference/entropia_metadata.md)
for the parsed form. Because the query spans several tables, collecting
it applies no column contract – timestamps stay raw integers and
`metadata` stays text (see
[`entropia_collect()`](https://humalab.github.io/EntropIA-R/reference/entropia_collect.md)).

The `text` column is the asset's best text layer per `source`: `"auto"`
(default) uses the extraction text when present, otherwise the
transcription – the app's FTS rule, assembled as one SQL `COALESCE`
expression. Markers are NOT stripped (use
[`entropia_text()`](https://humalab.github.io/EntropIA-R/reference/entropia_text.md)
for stripped text). Pass `text = FALSE` to omit the text layer entirely.

## Examples

``` r
con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
  package = "entropiaR"
))
entropia_corpus(con)
#> # A query:  ?? x 19
#> # Database: sqlite 3.53.3 [/home/runner/work/_temp/Library/entropiaR/extdata/entropia-example.sqlite]
#>   item_id      item_title collection_id metadata item_created_at item_updated_at
#>   <chr>        <chr>      <chr>         <chr>            <int64>         <int64>
#> 1 22222222-22… Manifiest… 11111111-111… "{\"__e…   1768478460000   1768478520000
#> 2 22222222-22… Manifiest… 11111111-111… "{\"__e…   1768478460000   1768478520000
#> 3 22222222-22… Manifiest… 11111111-111… "{\"__e…   1768478460000   1768478520000
#> 4 22222222-22… Carta al … 11111111-111… "{\"__e…   1768478580000   1768478640000
#> 5 22222222-22… Fotografí… 11111111-111…  NA        1768478700000   1768478760000
#> # ℹ 13 more variables: collection_name <chr>, collection_description <chr>,
#> #   collection_created_at <int64>, collection_updated_at <int64>,
#> #   asset_id <chr>, asset_path <chr>, asset_type <chr>, asset_size <int>,
#> #   asset_created_at <int64>, asset_sort_index <int>, parent_asset_id <chr>,
#> #   page_number <int>, text <chr>
entropia_corpus(con, collections = "Archivo de prueba", asset_types = "pdf")
#> # A query:  ?? x 19
#> # Database: sqlite 3.53.3 [/home/runner/work/_temp/Library/entropiaR/extdata/entropia-example.sqlite]
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
entropia_disconnect(con)
```
