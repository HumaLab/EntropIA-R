# entropiaR 0.0.0.9000 (development)

First development release. Read-only v1: the package reads EntropIA SQLite
databases and never writes to them.

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
