# entropiaR

A **read-only** interface between R and the SQLite databases from
[EntropIA](https://github.com/HumaLab/EntropIA-Pro-Lite).
Tidyverse style: explore the corpus — items, texts, entities, topics,
LLM results — without writing SQL.

The database is **always opened read-only**. Nothing in this package writes to it.

Spanish is the primary documentation language. This file is the English
secondary version. Articles: `vignette("connect")` (Spanish) /
`vignette("connect.en")` (English).

## Quick path

```r
library(entropiaR)
library(dplyr)

con <- entropia_connect(system.file(
  "extdata", "entropia-example.sqlite",
  package = "entropiaR"
))

# 1. What is in the corpus? SQL aggregates, no text download.
eda <- entropia_overview(con)
eda$counts
eda$collections

# 2. A reproducible dataset (one universe, one recipe).
ds <- entropia_analysis_dataset(
  con,
  asset_type == "pdf",
  name = "pdfs",
  text = FALSE
)
entropia_provenance(ds)$dataset_sha256

# 3. Plots from the same tables.
entropia_plot_collections(eda$collections)
entropia_plot_entities(eda$entities)
entropia_plot_coverage(eda$quality, metric = "ocr_coverage")

entropia_disconnect(con)
```

Expected: `eda$counts` reports items/assets/collections; the dataset is a
tibble with an `entropia_prov` stamp; `entropia_plot_*` return extensible
`ggplot` objects.

## Your own database

```r
# If EntropIA may be running, snapshot first (VACUUM INTO, WAL-aware).
live <- entropia_connect("path/to/entropia.sqlite")
snap <- tempfile(fileext = ".sqlite")
entropia_copy(live, snap)
entropia_disconnect(live)

con <- entropia_connect(snap)
```

Compatibility on open (`warn` by default):

```r
options(entropiaR.schema_policy = "warn")  # or "error" | "allow"
entropia_schema_compat(con)$compatible
```

Without the core tables (`collections`, `items`, `assets`), `warn` and `error`
refuse the connection. `allow` opens for diagnostics.

## Shared EDA

`entropia_overview()` aggregates **the selected universe** in SQL. It does not
materialise text or embeddings.

```r
eda <- entropia_overview(
  con,
  asset_types = c("pdf", "image"),
  page_assets = FALSE
)
eda$quality     # n, total, pct, status, group_id
eda$entities    # n = occurrences; pct = prevalence per item
eda$topics
attr(eda$temporal, "exclusions")
```

`entropia_profile()` profiles an already collected tibble:

```r
lengths <- entropia_text(con) |>
  entropia_collect() |>
  entropia_document_lengths()

entropia_profile(lengths, columns = c("n_chars", "n_words"))
```

Caveats the package does not hide:

| Fact | Consequence |
|---|---|
| `created_at` timestamps | Operational (created/imported), not necessarily the document date |
| entity `n` | Occurrences; `pct` is prevalence over items in the universe |
| Same collection names | Distinguished by `collection_id`, not by the label |
| PDF pages | Each page is an asset; an item is not “one document × N pages” |
| AI entities | Extractions, not verified facts |

## Dashboard and report

```r
# Does not open a browser: returns a shiny.appobj.
app <- entropia_dashboard(snap)
# shiny::runApp(app)

# Frozen HTML report (requires Quarto on PATH).
entropia_report(eda, "study.html")                 # redacts paths and labels
entropia_report(eda, "study-internal.html", redact = FALSE)
```

Shiny, bslib, ggplot2 and Quarto are **optional**. The core (connect, corpus,
overview, export) works without them.

## What the package covers

| Layer | Typical entry |
|---|---|
| Connection / schema | `entropia_connect()`, `entropia_copy()`, `entropia_schema_*()`, `entropia_validate()` |
| Lazy tables | `entropia_items()`, `entropia_entities()`, … + dplyr |
| Corpus and text | `entropia_corpus()`, `entropia_text()`, `entropia_metadata()`, `entropia_search()` |
| EDA | `entropia_overview()`, `entropia_profile()` |
| Analysis | `entropia_temporal_profile()`, `entropia_*_frequency()`, `entropia_compare_collections()` |
| Datasets | `entropia_analysis_dataset()`, `entropia_provenance()`, `entropia_export()` |
| Plots | `entropia_plot_*()` (Suggests: ggplot2) |
| Apps | `entropia_dashboard()`, `entropia_report()` |

## Documentation

Articles (vignettes), Spanish first, English with the `.en` suffix:

1. `vignette("connect")` / `vignette("connect.en")` — open, validate, snapshot
2. `vignette("corpus")` / `vignette("corpus.en")` — collections, items, assets
3. `vignette("text")` / `vignette("text.en")` — OCR, transcriptions, metadata
4. `vignette("dplyr")` / `vignette("dplyr.en")` — lazy filters and typing
5. `vignette("eda")` / `vignette("eda.en")` — overview and profile
6. `vignette("visualize")` / `vignette("visualize.en")` — individual plots
7. `vignette("datasets")` / `vignette("datasets.en")` — provenance v2 and export
8. `vignette("analysis")` / `vignette("analysis.en")` — a complete analysis
9. `vignette("dashboard")` / `vignette("dashboard.en")` — Shiny and Quarto
10. `vignette("administration")` / `vignette("administration.en")` — read-only, WAL, write stubs

Site: <https://humalab.github.io/EntropIA-R/>

## Status

Early development, **v1 read-only**. Stubs `entropia_insert/update/upsert/delete`
fail with `entropia_error_write_disabled`. Real writes: v2.

Requires **R >= 4.1**.

## License

MIT.

---

[Versión en español](README.md)
