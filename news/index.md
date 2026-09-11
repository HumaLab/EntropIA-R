# Changelog

## entropiaR 0.0.0.9001 (development)

This iteration turns the read-only core toward data analysts and
scientists: shared EDA tables, corrected analysis contracts, an optional
local dashboard and frozen Quarto reports. The database is still never
written.

### Correctness

- Temporal bucketing floors pre-epoch instants into their containing
  second/minute/hour instead of rounding toward zero, and every unit now
  returns a typed empty result on zero rows (week no longer errors).
- [`entropia_collect()`](https://humalab.github.io/EntropIA-R/reference/entropia_collect.md)
  infers types structurally through dbplyr’s query tree (base tables,
  projections, rename aliases); transformed expressions that merely
  reuse a manifest name stay raw, and an explicit `schema =` mapping is
  validated for joins. The old whole-SQL regex inference is gone.
- Collection identity:
  [`entropia_compare_collections()`](https://humalab.github.io/EntropIA-R/reference/entropia_compare_collections.md)
  groups by `collection_id` (labels retained), and quality/overview
  tables carry `group_id` so same-named collections never merge.
- [`entropia_metadata()`](https://humalab.github.io/EntropIA-R/reference/entropia_metadata.md)
  tolerates non-scalar `__entropia_file_metadata` fields, keeps the raw
  JSON and collided keys, and reports per-row diagnostics instead of
  aborting the whole parse.
- Schema compatibility now requires the core
  `collections`/`items`/`assets` tables at every version, so an empty or
  foreign SQLite file can no longer report `compatible = TRUE` under the
  default policy.
- CSV/TSV export writes real UTF-8 bytes under any locale (single binary
  connection, [`enc2utf8()`](https://rdrr.io/r/base/Encoding.html) +
  `useBytes`), and lazy exports complete a total order across all
  projected columns instead of trusting the first two.
- [`entropia_schema_info()`](https://humalab.github.io/EntropIA-R/reference/entropia_schema_info.md)
  reports live presence and SQLite type next to the expected manifest
  contract, and generated VIRTUAL columns are no longer hidden from
  introspection.
  [`entropia_connect()`](https://humalab.github.io/EntropIA-R/reference/entropia_connect.md)
  validates arguments and the policy before opening and guarantees
  disconnect on every post-open failure.

### Provenance v2

- Provenance separates structural identity (`schema_hash`), source
  identity (`snapshot_sha256`, from a self-contained file without a live
  WAL) and data identity (`dataset_sha256`, a canonical digest of the
  collected result), plus the resolved SQL and the full selection recipe
  with captured values.
- Reading provenance on a derived object re-computes the digest, reports
  `scope = "derived"` and preserves the origin digest/SQL — an origin
  query is never claimed to reproduce transformed rows.
- [`entropia_write_provenance()`](https://humalab.github.io/EntropIA-R/reference/entropia_write_provenance.md)
  accepts `redact = TRUE` to strip source paths and the origin query for
  shareable sidecars.
- [`entropia_analysis_dataset()`](https://humalab.github.io/EntropIA-R/reference/entropia_analysis_dataset.md)
  supports `unit = "item"|"asset"`, column projection, explicit text
  policy and the shared selection parameters (collections by id, asset
  types, pages, study date and inclusive range).

### Shared EDA

- [`entropia_overview()`](https://humalab.github.io/EntropIA-R/reference/entropia_overview.md)
  aggregates the whole study universe in SQLite and returns counts,
  per-collection rows, asset types, monthly temporal profile with
  exclusion counts, quality with eligibility/`no_data`/`not_applicable`
  statuses, entity/topic occurrence *and* distinct-item prevalence,
  schema inventory and the exact selection. No corpus text or BLOB is
  collected.
- [`entropia_profile()`](https://humalab.github.io/EntropIA-R/reference/entropia_profile.md)
  profiles collected tibbles locally: structure, missingness, numeric
  statistics, categorical distributions, exact-duplicate and
  key-duplicate counts, and opt-in reproducible sampling that leaves the
  caller’s RNG untouched.
- [`entropia_reconstruct_analysis()`](https://humalab.github.io/EntropIA-R/reference/entropia_reconstruct_analysis.md)
  resolves LLM targets in batched lookups per unique target instead of
  one query per row; targets are documented as current context, never as
  historical model input.

### Visualization

- Grouped temporal plots no longer draw one line across groups; entity
  bars never stack same-named values from different groups, with
  explicit `group`/`facet`/`top_by` controls and distinct-ID labels.
- New families: topics, missingness, collections, distributions
  (histogram/ECDF/boxplot with optional log scale), scatter and
  correlation heatmaps (numeric columns only, ID-like names excluded).
  Empty selections render annotated no-data states instead of silently
  dropping rows.

### Dashboard & reports (optional)

- `entropia_dashboard(path)` builds a `shiny.appobj` over a snapshot:
  one read-only connection per session pinned to one read transaction, a
  shared applied selection across
  summary/quality/exploration/detail/export panels, server-side
  pagination, on-demand text, bounded downloads with redacted
  provenance, and explicit caveats (operational dates are not document
  dates; AI-extracted entities are not verified facts). Shiny/bslib stay
  in Suggests.

- [`entropia_report()`](https://humalab.github.io/EntropIA-R/reference/entropia_report.md)
  renders the overview tables into a frozen Quarto dashboard with
  optional redaction of paths and identifying labels; it never
  re-queries the database from the browser.

- Connection & administration:
  [`entropia_connect()`](https://humalab.github.io/EntropIA-R/reference/entropia_connect.md)
  (read-only, schema compatibility policy, S3/S4 typed connection),
  [`entropia_disconnect()`](https://humalab.github.io/EntropIA-R/reference/entropia_disconnect.md),
  [`entropia_copy()`](https://humalab.github.io/EntropIA-R/reference/entropia_copy.md)
  (WAL-aware snapshot),
  [`entropia_status()`](https://humalab.github.io/EntropIA-R/reference/entropia_status.md),
  [`entropia_validate()`](https://humalab.github.io/EntropIA-R/reference/entropia_validate.md),
  [`entropia_schema_version()`](https://humalab.github.io/EntropIA-R/reference/entropia_schema_version.md),
  [`entropia_schema_info()`](https://humalab.github.io/EntropIA-R/reference/entropia_schema_info.md),
  [`entropia_schema_compat()`](https://humalab.github.io/EntropIA-R/reference/entropia_schema_compat.md).

- Entity access: one lazy `tbl_sql` accessor per readable table
  ([`entropia_items()`](https://humalab.github.io/EntropIA-R/reference/entropia_items.md),
  [`entropia_assets()`](https://humalab.github.io/EntropIA-R/reference/entropia_assets.md),
  [`entropia_entities()`](https://humalab.github.io/EntropIA-R/reference/entropia_entities.md),
  [`entropia_chunks()`](https://humalab.github.io/EntropIA-R/reference/entropia_chunks.md),
  …) with the column contract applied on
  [`entropia_collect()`](https://humalab.github.io/EntropIA-R/reference/entropia_collect.md)
  (millisecond timestamps → `POSIXct`, JSON-in-TEXT → list-columns,
  embedding BLOBs opt-in).

- Search:
  [`entropia_search()`](https://humalab.github.io/EntropIA-R/reference/entropia_search.md)
  — parameter-safe FTS5 search over the items and chunk indexes.

- Domain layer:
  [`entropia_corpus()`](https://humalab.github.io/EntropIA-R/reference/entropia_corpus.md),
  [`entropia_text()`](https://humalab.github.io/EntropIA-R/reference/entropia_text.md),
  [`entropia_metadata()`](https://humalab.github.io/EntropIA-R/reference/entropia_metadata.md),
  OCR/metadata coverage helpers,
  [`entropia_corpus_quality()`](https://humalab.github.io/EntropIA-R/reference/entropia_corpus_quality.md),
  [`entropia_orphans()`](https://humalab.github.io/EntropIA-R/reference/entropia_orphans.md).

- Research layer:
  [`entropia_entity_relations()`](https://humalab.github.io/EntropIA-R/reference/entropia_entity_relations.md),
  [`entropia_reconstruct_analysis()`](https://humalab.github.io/EntropIA-R/reference/entropia_reconstruct_analysis.md),
  [`entropia_conversation()`](https://humalab.github.io/EntropIA-R/reference/entropia_conversation.md).

- Sync metadata:
  [`entropia_sync_info()`](https://humalab.github.io/EntropIA-R/reference/entropia_sync_info.md)
  (whitelisted `sync_meta` keys typed to their R types, never raw
  `app_settings` secrets),
  [`entropia_sync_versions()`](https://humalab.github.io/EntropIA-R/reference/entropia_sync_versions.md),
  [`entropia_conflicts()`](https://humalab.github.io/EntropIA-R/reference/entropia_conflicts.md)
  (`reason` enum documented).

- Analysis & visualization: temporal/entity/topic/collection helpers,
  reproducible
  [`entropia_analysis_dataset()`](https://humalab.github.io/EntropIA-R/reference/entropia_analysis_dataset.md)
  with provenance, ggplot2 helpers.

- Export:
  [`entropia_export()`](https://humalab.github.io/EntropIA-R/reference/entropia_export.md)
  (csv/tsv/json/rds/parquet/arrow, streamed for lazy inputs),
  [`entropia_provenance()`](https://humalab.github.io/EntropIA-R/reference/entropia_provenance.md)
  /
  [`entropia_write_provenance()`](https://humalab.github.io/EntropIA-R/reference/entropia_write_provenance.md).

- Write API: v1 stubs (`entropia_insert/update/upsert/delete`) error
  with clear v2 guidance.

- Lifecycle & messages: the analysis layer carries the `experimental`
  lifecycle badge; the deprecation policy
  ([`lifecycle::deprecate_warn()`](https://lifecycle.r-lib.org/reference/deprecate_soft.html),
  one-release grace) is documented in the package help. Every exported
  error and warning is cli-formatted with a stable condition class —
  including a new `entropia_warn_malformed_json` class for tolerant JSON
  reads — and no bare
  [`stop()`](https://rdrr.io/r/base/stop.html)/[`warning()`](https://rdrr.io/r/base/warning.html)
  remains in `R/`.

- Performance: the corpus, FTS search, and entity-relations joins
  resolve every lookup table through an index (`EXPLAIN QUERY PLAN`
  verified); a smoke test enforces that the corpus join never full-scans
  a joined table.

- Dependencies: dropped the unused `stringr` import. Marker stripping
  runs in SQL (recursive CTE) and search-term hygiene is handled by
  `dbQuoteString`, so no string helper is needed — removing it also
  clears the last `R CMD check` note.

- Bug fixes: malformed JSON cells carrying bytes that are not valid
  UTF-8 (real corpus newspaper text) no longer crash the cli warning
  formatter — a new `ent_sanitize_msg()` helper replaces invalid bytes
  before interpolation, so
  [`entropia_collect()`](https://humalab.github.io/EntropIA-R/reference/entropia_collect.md)/[`entropia_metadata()`](https://humalab.github.io/EntropIA-R/reference/entropia_metadata.md)
  keep their tolerant warn-and-NA posture. The pkgdown config is
  YAML-parseable again (an unquoted `desc:` value was blocking
  [`pkgdown::build_site()`](https://pkgdown.r-lib.org/reference/build_site.html)).
