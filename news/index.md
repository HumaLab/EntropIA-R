# Changelog

## entropiaR 0.0.0.9000 (development)

First development release. Read-only v1: the package reads EntropIA
SQLite databases and never writes to them.

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
