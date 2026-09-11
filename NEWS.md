# entropiaR 0.0.0.9001 (development)

This iteration turns the read-only core toward data analysts and scientists:
shared EDA tables, corrected analysis contracts, an optional local dashboard
and frozen Quarto reports. The database is still never written.

## Correctness

* Temporal bucketing floors pre-epoch instants into their containing
  second/minute/hour instead of rounding toward zero, and every unit now
  returns a typed empty result on zero rows (week no longer errors).
* `entropia_collect()` infers types structurally through dbplyr's query tree
  (base tables, projections, rename aliases); transformed expressions that
  merely reuse a manifest name stay raw, and an explicit `schema =` mapping is
  validated for joins. The old whole-SQL regex inference is gone.
* Collection identity: `entropia_compare_collections()` groups by
  `collection_id` (labels retained), and quality/overview tables carry
  `group_id` so same-named collections never merge.
* `entropia_metadata()` tolerates non-scalar `__entropia_file_metadata`
  fields, keeps the raw JSON and collided keys, and reports per-row
  diagnostics instead of aborting the whole parse.
* Schema compatibility now requires the core `collections`/`items`/`assets`
  tables at every version, so an empty or foreign SQLite file can no longer
  report `compatible = TRUE` under the default policy.
* CSV/TSV export writes real UTF-8 bytes under any locale (single binary
  connection, `enc2utf8()` + `useBytes`), and lazy exports complete a total
  order across all projected columns instead of trusting the first two.
* `entropia_schema_info()` reports live presence and SQLite type next to the
  expected manifest contract, and generated VIRTUAL columns are no longer
  hidden from introspection. `entropia_connect()` validates arguments and the
  policy before opening and guarantees disconnect on every post-open failure.

## Provenance v2

* Provenance separates structural identity (`schema_hash`), source identity
  (`snapshot_sha256`, from a self-contained file without a live WAL) and data
  identity (`dataset_sha256`, a canonical digest of the collected result),
  plus the resolved SQL and the full selection recipe with captured values.
* Reading provenance on a derived object re-computes the digest, reports
  `scope = "derived"` and preserves the origin digest/SQL — an origin query is
  never claimed to reproduce transformed rows.
* `entropia_write_provenance()` accepts `redact = TRUE` to strip source paths
  and the origin query for shareable sidecars.
* `entropia_analysis_dataset()` supports `unit = "item"|"asset"`, column
  projection, explicit text policy and the shared selection parameters
  (collections by id, asset types, pages, study date and inclusive range).

## Shared EDA

* `entropia_overview()` aggregates the whole study universe in SQLite and
  returns counts, per-collection rows, asset types, monthly temporal profile
  with exclusion counts, quality with eligibility/`no_data`/`not_applicable`
  statuses, entity/topic occurrence *and* distinct-item prevalence,
  schema inventory and the exact selection. No corpus text or BLOB is
  collected.
* `entropia_profile()` profiles collected tibbles locally: structure,
  missingness, numeric statistics, categorical distributions, exact-duplicate
  and key-duplicate counts, and opt-in reproducible sampling that leaves the
  caller's RNG untouched.
* `entropia_reconstruct_analysis()` resolves LLM targets in batched lookups
  per unique target instead of one query per row; targets are documented as
  current context, never as historical model input.

## Visualization

* Grouped temporal plots no longer draw one line across groups; entity bars
  never stack same-named values from different groups, with explicit
  `group`/`facet`/`top_by` controls and distinct-ID labels.
* New families: topics, missingness, collections, distributions
  (histogram/ECDF/boxplot with optional log scale), scatter and correlation
  heatmaps (numeric columns only, ID-like names excluded). Empty selections
  render annotated no-data states instead of silently dropping rows.

## Dashboard & reports (optional)

* `entropia_dashboard(path)` builds a `shiny.appobj` over a snapshot: one
  read-only connection per session pinned to one read transaction, a shared
  applied selection across summary/quality/exploration/detail/export panels,
  server-side pagination, on-demand text, bounded downloads with redacted
  provenance, and explicit caveats (operational dates are not document dates;
  AI-extracted entities are not verified facts). Shiny/bslib stay in Suggests.
* `entropia_report()` renders the overview tables into a frozen Quarto
  dashboard with optional redaction of paths and identifying labels; it never
  re-queries the database from the browser.

* Connection & administration: `entropia_connect()` (read-only, schema
  compatibility policy, S3/S4 typed connection), `entropia_disconnect()`,
  `entropia_copy()` (WAL-aware snapshot), `entropia_status()`,
  `entropia_validate()`, `entropia_schema_version()`, `entropia_schema_info()`,
  `entropia_schema_compat()`.
* Entity access: one lazy `tbl_sql` accessor per readable table
  (`entropia_items()`, `entropia_assets()`, `entropia_entities()`,
  `entropia_chunks()`, …) with the column contract applied on
  `entropia_collect()` (millisecond timestamps → `POSIXct`, JSON-in-TEXT →
  list-columns, embedding BLOBs opt-in).
* Search: `entropia_search()` — parameter-safe FTS5 search over the items and
  chunk indexes.
* Domain layer: `entropia_corpus()`, `entropia_text()`, `entropia_metadata()`,
  OCR/metadata coverage helpers, `entropia_corpus_quality()`,
  `entropia_orphans()`.
* Research layer: `entropia_entity_relations()`,
  `entropia_reconstruct_analysis()`, `entropia_conversation()`.
* Sync metadata: `entropia_sync_info()` (whitelisted `sync_meta` keys typed to
  their R types, never raw `app_settings` secrets), `entropia_sync_versions()`,
  `entropia_conflicts()` (`reason` enum documented).
* Analysis & visualization: temporal/entity/topic/collection helpers,
  reproducible `entropia_analysis_dataset()` with provenance,
  ggplot2 helpers.
* Export: `entropia_export()` (csv/tsv/json/rds/parquet/arrow, streamed for
  lazy inputs), `entropia_provenance()` / `entropia_write_provenance()`.
* Write API: v1 stubs (`entropia_insert/update/upsert/delete`) error with clear
  v2 guidance.
* Lifecycle & messages: the analysis layer carries the `experimental` lifecycle
  badge; the deprecation policy (`lifecycle::deprecate_warn()`, one-release
  grace) is documented in the package help. Every exported error and warning
  is cli-formatted with a stable condition class — including a new
  `entropia_warn_malformed_json` class for tolerant JSON reads — and no bare
  `stop()`/`warning()` remains in `R/`.
* Performance: the corpus, FTS search, and entity-relations joins resolve every
  lookup table through an index (`EXPLAIN QUERY PLAN` verified); a smoke test
  enforces that the corpus join never full-scans a joined table.
* Dependencies: dropped the unused `stringr` import. Marker stripping runs in
  SQL (recursive CTE) and search-term hygiene is handled by `dbQuoteString`, so
  no string helper is needed — removing it also clears the last `R CMD check`
  note.
* Bug fixes: malformed JSON cells carrying bytes that are not valid UTF-8
  (real corpus newspaper text) no longer crash the cli warning formatter — a
  new `ent_sanitize_msg()` helper replaces invalid bytes before interpolation,
  so `entropia_collect()`/`entropia_metadata()` keep their tolerant warn-and-NA
  posture. The pkgdown config is YAML-parseable again (an unquoted `desc:`
  value was blocking `pkgdown::build_site()`).
