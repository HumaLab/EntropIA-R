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
* Analysis & visualization: temporal/entity/topic/collection helpers,
  reproducible `entropia_analysis_dataset()` with provenance,
  ggplot2 helpers.
* Export: `entropia_export()` (csv/tsv/json/rds/parquet/arrow, streamed for
  lazy inputs), `entropia_provenance()` / `entropia_write_provenance()`.
* Write API: v1 stubs (`entropia_insert/update/upsert/delete`) error with clear
  v2 guidance.
