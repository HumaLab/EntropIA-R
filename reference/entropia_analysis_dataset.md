# Build a reproducible analysis dataset

**\[experimental\]**

## Usage

``` r
entropia_analysis_dataset(
  con,
  ...,
  name = NULL,
  unit = "asset",
  columns = NULL,
  text = "auto",
  page_assets = TRUE,
  collection_ids = NULL,
  asset_types = NULL,
  date_var = "item_created_at",
  date_range = NULL
)
```

## Arguments

- con:

  A connection returned by
  [`entropia_connect()`](https://humalab.github.io/EntropIA-R/reference/entropia_connect.md).

- ...:

  Filter expressions applied to the corpus, e.g.
  `asset_type == "image"`. Column names resolve against the lazy corpus
  (see
  [`entropia_corpus()`](https://humalab.github.io/EntropIA-R/reference/entropia_corpus.md)
  for the full column set). Must be unnamed.

- name:

  Optional human-readable label stored in the provenance.

- unit:

  Observation unit, `"asset"` or `"item"`. Asset observations retain
  corpus rows for items without assets. Item observations use the same
  selected universe, with one row per item and no asset columns.

- columns:

  Optional character vector of output columns, in output order.

- text:

  Text source accepted by the corpus, or `FALSE` to omit text. Item text
  combines nonmissing asset texts in asset-ID order, separated by two
  newlines; no text yields `NA_character_`.

- page_assets:

  Include page assets.

- collection_ids:

  Collection IDs; `NULL` selects all, empty selects none.

- asset_types:

  Optional asset types.

- date_var:

  Corpus timestamp used for date filtering.

- date_range:

  Inclusive two-element Date or POSIXct range, or `NULL`.

## Value

A plain tibble with the `entropia_prov` attribute. Provenance includes
selected row/item/asset counts and exclusions due to item reduction.
Strict reproducibility requires an explicit
[`entropia_copy()`](https://humalab.github.io/EntropIA-R/reference/entropia_copy.md)
snapshot: hashing a live source file does not make it immutable.

## Details

The dataset boundary of the package: assembles the lazy corpus
([`entropia_corpus()`](https://humalab.github.io/EntropIA-R/reference/entropia_corpus.md)),
applies any filter expressions passed in `...`, and materialises the
result in `item_id`, `asset_id` order. The returned plain tibble carries
an `entropia_prov` attribute recording the build recipe:

- `name`: the human label passed to `name` (`NULL` for unnamed);

- `schema_version`: the database schema head (e.g. `"0029_rag_chunks"`);

- `schema_hash`: the connection's schema hash;

- `snapshot_sha256`: source-file hash, unavailable with a nonempty WAL;

- `dataset_sha256`: canonical values, column classes and row order;

- `query`: resolved SQL, with `selection` recording subsequent item
  reduction;

- `source_path`: the database file the dataset was built from;

- `filters`: the deparsed filter expressions captured from `...`;

- `package_version`: the entropiaR version used;

- `built_at`: the build timestamp (ISO-8601, UTC);

- `r_version`: the R version used.

Building the same dataset twice against an unchanged database yields
byte-identical rows (deterministic ordering) and identical provenance
apart from `built_at`. Read the stamp with
[`entropia_provenance()`](https://humalab.github.io/EntropIA-R/reference/entropia_provenance.md)
and persist it as a JSON sidecar with
[`entropia_write_provenance()`](https://humalab.github.io/EntropIA-R/reference/entropia_write_provenance.md).

## Examples

``` r
con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
  package = "entropiaR"
))
ds <- entropia_analysis_dataset(con, asset_type == "pdf", name = "PDF corpus")
#> Warning: Missing values are always removed in SQL aggregation functions.
#> Use `na.rm = TRUE` to silence this warning
#> This warning is displayed once every 8 hours.
entropia_provenance(ds)
#> entropiaR dataset provenance
#>   name:           PDF corpus
#>   schema version: 0029_rag_chunks
#>   schema hash:    09d4c603b66d68c4c0cef0f51ff09a04fb30a49fe200907ef69693d11dd25732
#>   dataset hash:   1994ab82411fd92a1e09cf8caf392cb8720691b8d07903bad7d4bac1faa22ecf
#>   scope:          origin
#>   source path:    /home/runner/work/_temp/Library/entropiaR/extdata/entropia-example.sqlite
#>   filters:        asset_type == "pdf"
#>   package:        0.0.0.9000
#>   built at:       2026-09-11T18:06:52.011Z
#>   R version:      R version 4.6.1 (2026-06-24)
entropia_disconnect(con)
```
