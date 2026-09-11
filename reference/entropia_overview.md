# Overview of a selected study universe

Aggregates the shared study query in SQLite. Raw text, metadata and
BLOBs are never materialised. Counts exclude NULL IDs. Collections
retain their IDs and may have zero selected items. Temporal counts count
study rows, using UTC month starts; missing and invalid dates are
recorded in the temporal tibble's `exclusions` attribute. Metadata
validity is JSON syntax validity, not a claim about the meaning of
metadata.

## Usage

``` r
entropia_overview(
  con,
  collection_ids = NULL,
  asset_types = NULL,
  page_assets = TRUE,
  date_var = "item_created_at",
  date_range = NULL,
  text_source = "auto",
  entity_source = NULL,
  model_name = NULL,
  min_confidence = NULL
)
```

## Arguments

- con:

  A connection returned by
  [`entropia_connect()`](https://humalab.github.io/EntropIA-R/reference/entropia_connect.md).

- collection_ids:

  Collection IDs, NULL for all; an empty vector selects none.

- asset_types:

  Asset types, NULL for all.

- page_assets:

  Include page assets.

- date_var:

  One of item_created_at, item_updated_at, asset_created_at,
  collection_created_at or collection_updated_at.

- date_range:

  NULL or an inclusive two-element Date/POSIXct range.

- text_source:

  Text source: auto, extraction or transcription.

- entity_source:

  Optional entity source values. Soft-deleted entities are excluded
  unless explicitly selected.

- model_name:

  Optional entity model names.

- min_confidence:

  Optional entity confidence threshold between 0 and 1.

## Value

An ordinary list with counts, collections, asset_types, temporal,
quality, entities, topics, inventory, selection and provenance. All
tabular elements are plain tibbles. Provenance is lightweight origin
metadata, not a snapshot or result digest.

## Details

Text eligibility is based on asset type: OCR for image/PDF and
transcription for audio/video. Automatic selection prefers a present
extraction over transcription, even if that extraction is empty.
`empty_text` retains the legacy any-layer definition;
`selected_text_empty` and `selected_text_usable` describe the requested
source separately. Quality status distinguishes `ok`, `empty`,
`invalid`, `no_data` and `not_applicable`. Percentages are fractions,
not percentages multiplied by 100. Entity/topic `n` counts occurrences,
while `pct` is distinct item prevalence over all selected items.
Asset-scoped entities must belong to a selected asset; item-scoped
entities need only a selected item.
