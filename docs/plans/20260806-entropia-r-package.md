# entropiaR — Official R Interface for EntropIA SQLite Data

## Overview

Build `entropiaR`, a production-quality R package that is the native, idiomatic,
stable interface between R and the SQLite database (`entropia.sqlite`) generated
by the EntropIA desktop app. The package follows tidyverse philosophy: tabular
objects as tibbles, pipes, consistent verbs, tidy evaluation, lazy `tbl_sql`
queries that stay on SQLite, composable APIs, clear typed functions, actionable
error messages, full documentation, exhaustive tests, and minimal RAM usage.

**v1 scope (decided):** read-only. The package opens the database in read-only
mode by default; the write API is designed in this plan (architecture, security
model, verb signatures) but implemented as clear stubs that error, with full
implementation deferred to v2. Analysis, visualization, export, diagnostics and
schema compatibility are all part of v1.

**Package name (decided):** `entropiaR` — mirrors the repo `EntropIA-R`, is
instantly recognizable as the R interface, and mixed-case package names have
precedents (`DBI`, `R6`, `Rcpp`) for GitHub-first distribution.

**Testing approach (decided):** TDD (testthat 3e). Every task writes its tests
with/just before the code; no task is complete with failing tests.

Integration: the package is developed in this repo (`EntropIA-R`), with
`data-test/entropia.sqlite` available as a reference corpus (never as a test
fixture — see Testing Strategy).

## Context (from discovery)

### Sources of truth (audited, 2026-08-06)

| Artifact | Location | Role |
| --- | --- | --- |
| Migrations registry | `EntropIA-Pro-Lite/packages/store/src/runner.ts` (`MIGRATIONS`, 0001–0029) | Source of truth for schema DDL. The `.sql/` folder is a **stale partial mirror** — do not use it. |
| Runtime repairs | `EntropIA-Pro-Lite/apps/desktop/src-tauri/src/lib.rs` | Rust-side idempotent DDL (indexes, `app_settings`, `extractions` CHECK drop, `layouts`, `rag_asset_embedding_state`) that can exist **before/without** a `_migrations` entry. |
| Sync engine | `EntropIA-Pro-Lite/apps/desktop/src-tauri/src/sync/{schema,capture,push,apply}.rs` | Creates the 9 `sync_*` tables + 48 `trg_sync_*` triggers. |
| Sync protocol | `EntropIA-Cloud/docs/PROTOCOL.md` + `docs/DESIGN.md` | Wire contract, LWW conflict model, schema_tag semantics. |
| Canonical schema doc | `EntropIA-Pro-Lite/SQLite.md` | Best narrative reference. |
| Reference DB | `data-test/entropia.sqlite` (29 MB, gitignored) | Real corpus: 17 collections, 2393 items, 2477 assets, 1339 entities, 1648 rag_chunks, 12607 sync_row_versions. |

### Domain model (derived from real schema + code, not assumed)

```
collections (1) ──→ items (2393) ──→ assets (2477: image|pdf|audio)
                        │                ├─ pdf pages: parent_asset_id + page_number (partial UNIQUE)
                        │                └─ 1:1 children: extractions | transcriptions | layouts
                        ├─ notes (item-level or asset-scoped via nullable asset_id)
                        ├─ annotations (asset + page, kind ∈ rectangle|underline|crop|erase|rotation)
                        ├─ topics / item_topics (names normalized UPPERCASE, UNIQUE)
                        ├─ entities (NER; entity_type; source + model_name provenance; geo; soft-delete)
                        ├─ triples (S/P/O, optional asset_id)
                        ├─ llm_results (target_type ∈ asset|item|collection|unknown; job_type; result JSON)
                        └─ rag_conversations / rag_messages (role ∈ user|assistant; sources JSON)
```
Not synced but readable: `vec_assets` (embedding BLOB), `rag_chunks` + `rag_chunks_fts`
(chunking contract `rag-chunk-800-100-char-v1`, embedding `baai/bge-m3` 1024 dims),
`fts_items` (contentless FTS5), `app_settings` (contains secrets — do not surface by default).

### Schema versioning (the compatibility contract)

- **No numeric version.** `PRAGMA user_version` = 0, unused. `PRAGMA application_id` = 0.
- The authoritative version is **`MAX(name)` in `_migrations`** (currently `0029_rag_chunks`).
  The sync `X-Schema-Tag` header uses the same head, compared lexicographically.
- EntropIA applies migrations idempotently at startup; Rust repairs can add DDL
  without a migration entry. An R reader must tolerate tables present without a
  `_migrations` row and columns present without a migration.

### Critical schema facts the package must encapsulate

1. **Mixed timestamp units** — the single biggest trap:
   - epoch **ms** (13 digits): `items/assets/extractions/transcriptions/layouts/notes/annotations/topics/item_topics/llm_results/rag_*` `created_at`/`updated_at`; `sync_*` `changed_at`/`last_sync_at`.
   - epoch **seconds** (10 digits): `_migrations.applied_at`; the **DDL default** for `entities.created_at` and `triples.created_at` (`strftime('%s','now')`).
   - **In practice the app writes ms into `entities/triples.created_at`** (verified: 13-digit values), so the type map uses a magnitude-guarded `datetime_auto` for those two columns — the same `< 1e12 ⟹ seconds` guard EntropIA itself used in migration 0019.
   - ISO-8601 strings inside JSON: `items.metadata.__entropia_file_metadata.importedAt`.
2. **JSON inside TEXT columns**: `items.metadata`, `transcriptions.segments` (array of `{start_ms,end_ms,text}`), `layouts.regions`/`blocks`, `rag_messages.sources`, `llm_results.result`, `sync_conflicts.loser_payload/winner_summary`.
3. **Conceptual FKs with no physical constraint**: `notes/entities/triples.asset_id` (NULL = item-level), `llm_results.target_id`, `rag_chunks.source_id`. `PRAGMA foreign_keys` is ON in the app but only where declared.
4. **Soft-deleted entities**: `source = 'manual_deleted'` rows persist but are hidden by the app. Default accessor excludes them; opt-in `include_deleted`.
5. **PDF OCR markers**: extraction text embeds `![](page=n,bbox=[...])` markers (verified: 27/258). The text layer offers stripping.
6. **Contentless FTS5**: `fts_items` declared columns read NULL without a join — **always** `items i ON i.rowid = fts_items.rowid`. `rag_chunks_fts` is a regular FTS5 (has `_content`), join on `chunk_id ↔ rag_chunks.id`.
7. **Embedding BLOBs**: raw little-endian `f32` vectors (1024 dims = 4096 bytes). Never selected by default in joins; accessors exclude the `embedding` column unless explicitly requested.
8. **81 triggers guard integrity**: 48 `trg_sync_*` (oplog capture, gated by `sync_meta.capture_enabled`/`applying`) + 33 `collection_activity_*` (maintain `collections.updated_at`). Any write path must respect them; `INSERT OR REPLACE` is banned by the sync engine (rowid reassignment breaks FTS5).
9. **Deterministic IDs** (useful for joins): `extractions.id = 'ext-'||asset_id`, `transcriptions.id = 'trx-'||asset_id`, `layouts.id = 'lay-'||asset_id`, `llm_results.id = 'llr-{target_type}-{target_id}-{job_type}'`, `rag_chunks.id = 'ragchk-'||sha256`. All other PKs are TEXT UUIDv4. `vec_assets` PK is `asset_id`.
10. **WAL journal mode**: `-wal`/`-shm` sidecars exist while the app runs. Open read-only (or copy the triplex) — never open the live DB read-write.
11. **`app_settings` holds API secrets** (`*_api_key`) and is blocked from generic IPC in the app. The package exposes a whitelisted subset (e.g. `language`, `llm_mode`, `embedding_provider`) only, never raw values of secret keys.
12. Migrations 0010/0019/0025 rebuilt tables via DROP+RENAME (triggers/indexes recreated); 0019 normalized legacy `llm_results.created_at` seconds→ms; 0023 rewrote PKs to deterministic formats. Old DBs may lack `target_type` (pre-0019) or carry legacy tables (`jobs`, `vec_items`, `embeddings_fallback`).

### Sync tables (what a read-only consumer should touch)

- **Read-safe**: `sync_meta` (device_id, server_url, account_email, last_pull_seq, last_sync_at (ms), server_epoch, triggers_version, capture_enabled), `sync_row_versions` (`(table,row_id)→server_seq`), `sync_conflicts` (documented `reason` enum), `sync_blob_index` (content-derivable cache).
- **Ignore (pure internals)**: `sync_oplog`, `sync_pending_rows`, `sync_pending_blobs`, `sync_pending_fts`, `sync_topic_aliases`.

## Architecture

### Layering (kept strictly separate)

```
┌─ entropiaR ────────────────────────────────────────────────────────┐
│ access:  entropia_connect · entropia_*(con) → tbl_sql (lazy, SQL)  │
│ type:    entropia_collect() → tibble (datetime/JSON/BLOB applied)  │
│ domain:  entropia_corpus/text/metadata/quality/*coverage (tbl_sql) │
│ analysis: functions on tibbles (temporal, entities, topics, comps) │
│ viz:     ggplot helpers on analysis summaries (Suggests)           │
│ export:  entropia_export(x, path, format) (Suggests for parquet)   │
│ write:   v2 stubs erroring with clear guidance (v1)                │
└─────────────────────────────────────────────────────────────────────┘
```
Data access, transformation, analysis and visualization are separate — no
monolithic functions.

### Dependencies (decided)

**Imports** (hard, minimal): `DBI`, `RSQLite`, `dbplyr`, `dplyr`, `tibble`,
`rlang`, `cli`, `lifecycle`, `jsonlite`, `tidyselect`, `stringr`.

Justification: DBI/RSQLite/dbplyr/dplyr/tibble are the core; rlang+cli for
errors; lifecycle for the API contract; jsonlite for the JSON-in-TEXT columns
(non-negotiable domain need); tidyselect for column-selection verbs; stringr
for the text layer (marker stripping, search-term hygiene).

**Suggests**: `testthat`, `ggplot2`, `tidyr`, `lubridate`, `forcats`, `arrow`,
`duckdb`, `knitr`, `rmarkdown`, `pkgdown`, `covr`, `lintr`, `styler`, `spelling`,
`withr`, `vdiffr` (viz tests).

**Avoided**: `vctrs` (no custom vector types in v1), `R6` (S3 suffices — no
architectural reason for R6), `glue` (cli covers), `fs` (base file ops suffice),
`purrr` (base `vapply`/`Map` where needed), `data.table`. `tidyr`/`lubridate`/
`forcats`/`ggplot2`/`arrow`/`duckdb` stay in Suggests — users opt in.

**Imports vs Suggests rule**: a suggested package may be used in exported code
only behind `requireNamespace()` with a clear error; never in Imports "just in
case".

### Public API (naming justified by domain)

Prefix `entropia_` everywhere (matches the connection verb the user proposed;
short, unambiguous, tab-completes well). Verb family naming, no magic.

**1. Connection & administration**
- `entropia_connect(path, write = FALSE, validate = TRUE, quiet = FALSE)` →
  returns a specialized connection. `path` accepts a file path or `:memory:`.
  Opens with `RSQLite::SQLite()` + `flags = SQLITE_RO_V2` and re-asserts
  `PRAGMA query_only = ON` (belt and braces). Runs schema compatibility check
  on open (policy via `options(entropiaR.schema_policy)`).
- `entropia_disconnect(con)` — closes, idempotent.
- `entropia_schema_version(con)` → character (e.g. `"0029_rag_chunks"`).
- `entropia_schema_info(con)` → tibble of tables + columns + types (from the
  column contract, with source `schema`/`manifest`).
- `entropia_status(con)` → compact summary: path, mode (read-only), schema
  version, row counts (top tables), sync freshness (`last_sync_at`), WAL state.
- `entropia_validate(con)` → diagnostics: missing core tables/columns, broken
  relationships, empty DB, unexpected values. Returns a tibble of findings.
- `entropia_copy(con, dest)` → WAL-aware snapshot copy (safe for analysis).

**2. Entity access** — each returns a lazy `tbl_sql` on the raw table (minimal
surprise, fully composable with dplyr):

| Function | Table | Notes |
| --- | --- | --- |
| `entropia_collections(con)` | collections | |
| `entropia_items(con)` | items | excludes the generated `search_text`? no — keeps it, it is cheap |
| `entropia_assets(con)` | assets | exposes `parent_asset_id`/`page_number` for PDF pages |
| `entropia_extractions(con)` | extractions | |
| `entropia_transcriptions(con)` | transcriptions | |
| `entropia_layouts(con)` | layouts | |
| `entropia_notes(con)` | notes | |
| `entropia_annotations(con)` | annotations | |
| `entropia_entities(con, include_deleted = FALSE, min_confidence = NULL)` | entities | excludes soft-deleted by default |
| `entropia_triples(con)` | triples | |
| `entropia_topics(con)` | topics | |
| `entropia_item_topics(con)` | item_topics | |
| `entropia_llm_results(con, target_type = NULL, job_type = NULL)` | llm_results | |
| `entropia_rag_conversations(con)` | rag_conversations | |
| `entropia_rag_messages(con)` | rag_messages | |
| `entropia_embeddings(con, with_vector = FALSE)` | vec_assets | `embedding` BLOB omitted unless requested |
| `entropia_chunks(con, with_vector = FALSE)` | rag_chunks | same BLOB rule |
| `entropia_search_index(con)` | fts_items | advanced; documented as raw contentless table |

**3. Queries / search**
- `entropia_search(con, query, index = c("items", "chunks"), limit = NULL)` →
  parameter-safe FTS5 search. `items` joins `fts_items.rowid ↔ items.rowid`
  (contentless contract); `chunks` joins `rag_chunks_fts.chunk_id ↔ rag_chunks.id`.
  Query text is escaped via `DBI::dbQuoteString` before splicing into `MATCH`
  (injection-safe). Returns `tbl_sql` with a `rank`-eligible ordering.

**4. Filtering / transform** — deliberately **no custom verbs**: `dplyr::filter`,
`select`, `mutate`, `summarise`, `group_by`, `arrange`, `left_join` work directly
on accessor results. tidyselect is supported natively (e.g.
`select(entropia_items(con), id, title)`).

**5. Collection / typing**
- `entropia_collect(x, n = Inf, ...)` — like `collect()` but applies the column
  contract: datetime columns → `POSIXct` (ms/auto-guard), JSON columns →
  list-columns via `jsonlite::fromJSON(..., simplifyVector = TRUE)`, BLOB →
  kept `raw` unless a `blob_f32` request. Never loads more than needed.
- `entropia_datetime(x)` / `entropia_datetime_s(x)` — pure helpers converting
  ms / seconds integer vectors to `POSIXct`; `entropia_datetime_auto(x)` uses
  the `< 1e12` magnitude guard (used for `entities`/`triples`).
- `entropia_typed(tbl)` — convenience: given a `tbl_sql` tagged with the column
  contract, returns a query that pre-translates only the cheap columns
  (documented as best-effort; the reliable path is `entropia_collect`).

**6. Domain layer** (high-level, research-oriented)
- `entropia_corpus(con, collections = NULL, asset_types = NULL, text = "auto",
  page_assets = TRUE, include_deleted = FALSE)` → the workhorse: lazy
  `items ⋈ collections ⋈ assets ⋈ text` (see below). `collections`/`asset_types`
  accept tidyselect-style character vectors.
- `entropia_text(con, assets = NULL, source = "auto", strip_markers = TRUE)` →
  per-asset best text. `source` ∈ `extraction|transcription|auto`; `auto`
  mirrors the app's FTS rule: extraction when present, else transcription.
  Implemented as one SQL expression (no R-side per-row loops).
- `entropia_metadata(con, items = NULL, parse = TRUE)` → `items.metadata`
  as tidy rows: `item_id`, plus parsed `__entropia_file_metadata` fields
  (`original_name`, `original_path`, `imported_at` as POSIXct) and any
  remaining top-level keys as list-columns.
- `entropia_ocr_coverage(con, by = c("collection", "item", "asset"))` →
  assets without extraction / with empty extraction text, per grouping.
- `entropia_metadata_coverage(con, by = "collection")` → items without metadata.
- `entropia_corpus_quality(con)` → combined report (OCR coverage, metadata
  coverage, transcription presence, empty texts).
- `entropia_orphans(con)` → broken references: items→collection, assets→item,
  extractions/transcriptions/layouts→asset, entities/triples→item, etc.
  (works around the missing physical FKs).

**7. Research layer**
- `entropia_entity_relations(con, min_confidence = NULL)` → triples joined to
  entity-friendly columns (subject/predicate/object + item/collection context).
- `entropia_entities(con, ...)` already exposes NER with provenance; geo
  columns documented (`geo_status`, `latitude`, `longitude`, manual overrides).
- `entropia_llm_results(con, ...)` + `entropia_reconstruct_analysis(con,
  target = NULL, job_type = NULL)` → joins `llm_results` back to its target
  (asset/item/collection by `target_type`) and parses `result`.
- `entropia_conversation(con, id)` → one conversation with ordered messages and
  parsed `sources` citations.

**8. Analysis** (operate on collected tibbles — separated from access)
- `entropia_temporal_profile(x, date_var, by = NULL)` → counts by time unit.
- `entropia_document_lengths(x, text_var = "text")` → chars/words per document.
- `entropia_entity_frequency(x)` → top entities by type/collection.
- `entropia_topic_frequency(x)` → items per topic.
- `entropia_compare_collections(x)` → per-collection summary table.
- `entropia_analysis_dataset(con, ..., name = NULL)` → builds a reproducible
  dataset: applies corpus + filters + `entropia_collect`, stamps provenance
  (see Reproducibility) and returns a tibble with class `entropia_dataset`.

**9. Export / interoperability**
- `entropia_export(x, path, format = c("csv", "tsv", "json", "rds", "parquet", "arrow"))`
  — csv/tsv/json/rds always available; parquet/arrow require the `arrow`
  Suggests. Streams large lazy queries in chunks (never `collect()` unbounded).
- `entropia_provenance(x)` / `entropia_write_provenance(x, path)` — JSON sidecar
  recording schema version, source path + content hash, filters, package version,
  timestamp (see Reproducibility).
- Future (documented, not implemented): DuckDB/Arrow as an optional analytical
  backend via `entropia_copy(..., format = "duckdb")`; Quarto/Shiny interop is
  natural (tibbles) and needs no code.

**10. Diagnostics & validation** — `entropia_validate`, `entropia_status`,
`entropia_schema_info` (above). Error classes (see Robustness).

### Object model (decided)

- **S3**. `entropia_connect()` returns the DBI connection with an added class:
  `class(con) <- c("entropia_conn", class(con))` plus attributes `path`,
  `mode`, `schema_version`, `content_hash`. This makes the object a real DBI
  connection (DBI/dbplyr functions all keep working) AND a typed one.
- Methods: `print.entropia_conn()`, `summary.entropia_conn()`,
  `format.entropia_conn()`, `dbIsValid.entropia_conn()` (reports closed state),
  `collect.entropia_conn()` (no-op with guidance — `entropia_collect` is the
  typed path).
- `entropia_dataset` class on analysis outputs: `print`/`glimpse`/`as_tibble`
  methods, provenance attributes.
- Results of entity accessors are plain `tbl_sql` (no subclass — keeps every
  dplyr/dbplyr function working with zero magic).
- **No** tibble subclasses, **no** vctrs types, **no** R6 in v1.

### Schema compatibility layer (the versioning strategy)

- On connect: read `_migrations`, compute version = `MAX(name)`.
- Package ships `inst/schemas/manifest.json`: the known-good column contract
  per table (name, type, required), tagged with the minimum migration that
  guarantees it. `0029_rag_chunks` is the shipped reference manifest.
- Policy: `options(entropiaR.schema_policy = "warn")` default:
  - version **unknown** (newer than shipped manifest) → warn + proceed
    (read-only, tolerant).
  - version **older** → warn + proceed if all **required** columns exist
    (manifest-driven), else error `entropia_error_schema_incompatible`.
  - `"error"` → hard stop on unknown; `"allow"` → silent.
- Column presence is re-checked live via `PRAGMA table_info` per used table
  (never trust the manifest alone — the app adds Rust-side DDL without
  migrations).
- Version-specific SQL isolated in `R/sql/` (e.g. pre-0019 `llm_results`
  lacking `target_type`) selected by the version string.
- Backward compatibility is the default posture: unknown columns are ignored,
  missing optional columns degrade gracefully, missing required columns error.

### Write model (v2 — designed now, stubbed in v1)

Read-only is enforced at the connection and at the verb level. In v1 every write
verb exists but calls `cli::cli_abort` with class
`entropia_error_write_disabled` and guidance to open `entropia_connect(path,
write = TRUE)` — which itself errors in v1. The v2 design, documented in
`vignettes/administration.Rmd`:

- `entropia_connect(write = TRUE)` opens read-write, sets `PRAGMA
  foreign_keys = ON`, and warns loudly that the DB may be live in EntropIA
  (WAL) and protected by 81 triggers.
- Verbs (all transactional via `DBI::dbWithTransaction`, all with
  `dry_run = TRUE` default and `confirm` for destructive ops):
  - `entropia_insert(con, table, data)` — validated against the column
    contract; generates UUIDs for missing PKs.
  - `entropia_update(con, table, data, by)` — `by` required; never updates
    PKs.
  - `entropia_upsert(con, table, data, by)` — implemented as
    `INSERT ... ON CONFLICT(id) DO UPDATE` (**never** `INSERT OR REPLACE` —
    rowid reassignment breaks FTS5).
  - `entropia_delete(con, table, filter)` — `filter` required (no full-table
    delete without `all = TRUE`), `confirm = TRUE` required.
- Manual SQL is avoided wherever DBI/dbplyr resolve correctly; parameterized
  statements only; triggers are respected (e.g. `collections.updated_at` is
  trigger-maintained — never written directly).
- Validation options: `options(entropiaR.write_dry_run = TRUE)` global guard.

### Robustness (error model)

All errors via `rlang::abort` with stable classes and `cli` formatted messages:

| Condition | Class | Behavior |
| --- | --- | --- |
| file missing | `entropia_error_not_found` | abort with path |
| not a SQLite file | `entropia_error_not_sqlite` | abort |
| schema incompatible | `entropia_error_schema_incompatible` | abort/warn per policy |
| DB locked / busy | `entropia_error_locked` | wrapped from RSQLite, action: copy triplex |
| table missing | `entropia_error_table_missing` | abort listing available tables |
| column missing | `entropia_error_column_missing` | abort listing alternatives |
| broken relationships | `entropia_error_broken_refs` | from `entropia_orphans` |
| unexpected types / NULL | detection in `entropia_collect` | warning + `NA` typed |
| empty DB | `entropia_validate` finding | warning, not error |
| write attempt in read-only v1 | `entropia_error_write_disabled` | abort with v2 guidance |

Unknown columns are a warning, not an error (forward compatibility).

### Performance

- **Lazy by construction**: every accessor returns `tbl_sql`; SQLite does the
  filtering/joining/aggregating. No `collect()` inside the package except in
  explicit collect/export/analysis surfaces.
- **Index utilization**: existing indexes cover the hot paths
  (`idx_assets_item`, `idx_items_collection`, `idx_entities_*`, `idx_rag_chunks_*`,
  FTS). The corpus join is index-friendly; verify with `EXPLAIN QUERY PLAN` in
  a task.
- **BLOB discipline**: `embedding` columns excluded from default selects;
  `with_vector = TRUE` is explicit. `entropia_corpus` never touches BLOBs.
- **Text assembly in SQL**: extraction-then-transcription per asset is one SQL
  expression (subquery/coalesce), not R-side loops — no N+1.
- **Streaming export**: `DBI::dbSendQuery` + `fetch(n)` chunks for csv/parquet.
- **Documented cost patterns**: joining `entities`→`items`→`collections` is the
  most expensive common query; `entropia_validate` and `entropia_orphans` are
  full-scan by nature — documented as O(n).
- **Snapshot**: `entropia_copy()` for long-running analysis (WAL-aware).
- DuckDB/Arrow remain a documented future option, not a v1 replacement.

### Public vs internal API / lifecycle

- **Exported (public)**: everything in the Public API above. ~40 functions.
- **Internal (unexported)**: `R/sql/` helpers, column-contract loader, datetime
  guards, marker-stripping internals, fixture builders. Explicit list in
  `_pkgdown.yml` reference index (only public fns documented).
- **Naming conventions**: public = `entropia_*`; internal = `ent_*` (e.g.
  `ent_sql_marker_pattern`, `ent_column_contract`); test helpers =
  `expect_entropia_*`.
- **Lifecycle**: new/experimental functions get `lifecycle::lifecycle()` badges
  (`experimental` for analysis layer in v1); deprecations via
  `lifecycle::deprecate_warn` with one-release grace; the manifest and column
  types are the compatibility surface — changes bump the manifest, never silent
  breaks.

### Reproducibility

- **Content hash**: `entropia_connect` computes `sha256` over the schema text
  (`sqlite_master` SQL) + `_migrations` rows — cheap, stable, distinguishes
  schema state without hashing 29 MB of data.
- **Provenance stamp**: `entropia_analysis_dataset()` attaches
  `entropia_prov` attributes: source path, content hash, schema version,
  package version, filter expressions (captured via rlang), timestamp, R version.
  `entropia_provenance(x)` reads it; `entropia_write_provenance(x, path)` writes
  JSON.
- **Determinism**: all export/collect paths `arrange()` deterministically; no
  sampling without an explicit seed argument; no dependence on row order.
- **Traceability**: filter/transform expressions are captured (rlang quosures)
  at the dataset boundary and stored in provenance.

## Package Structure

```
EntropIA-R/
├── DESCRIPTION, NAMESPACE, LICENSE, LICENSE.md, README.md, NEWS.md
├── _pkgdown.yml, .Rbuildignore, .gitignore, .editorconfig
├── R/
│   ├── entropiaR-package.R     # package doc + reexports (|> , .data)
│   ├── connect.R               # connect/disconnect, S3 class, print/summary/format
│   ├── schema.R                # version detection, compat layer, manifest loader
│   ├── validate.R              # entropia_validate, entropia_status, entropia_schema_info
│   ├── tables.R                # entity accessors (one short fn per table)
│   ├── corpus.R                # entropia_corpus, entropia_text, entropia_metadata
│   ├── quality.R               # ocr/metadata coverage, corpus_quality, orphans
│   ├── research.R              # search, entity_relations, llm reconstruction, conversations
│   ├── collect.R               # entropia_collect, datetime helpers, JSON/BLOB typing
│   ├── analysis.R              # temporal/entity/topic/compare + entropia_analysis_dataset
│   ├── plot.R                  # ggplot helpers (Suggests)
│   ├── export.R                # entropia_export, streaming, provenance I/O
│   ├── write.R                 # v2 stubs (error classes + documented signatures)
│   ├── sql.R                   # versioned SQL (R/sql/), FTS MATCH builder
│   ├── utils.R                 # ent_* internals
│   └── zzz.R                   # .onLoad: options, package-level defaults
├── R/sql/                      # versioned SQL fragments (pre-0019 etc.)
├── inst/schemas/manifest.json  # column contract
├── inst/extdata/               # small example fixtures for docs
├── data-raw/                   # fixture/sample-DB builder scripts (never the user DB)
├── tests/testthat/
│   ├── fixtures/               # minimal SQLite fixtures (generated, gitignored artifacts)
│   ├── helper-fixtures.R       # builders: mini schema, full schema, legacy variants
│   ├── helper-expect.R         # expect_entropia_* matchers
│   └── test-*.R                # one file per module
├── man/                        # roxygen2
├── vignettes/                  # see Documentation
└── .github/workflows/          # R-CMD-check.yaml, lint.yaml, pkgdown.yaml, coverage.yaml
```

Granularity rule: one file per module (13 source files), no file over ~400
lines; a module is a concern, not a function.

## Testing Strategy

- **testthat 3e**, `test_local()`. TDD per task (tests written with the code).
- **Fixture policy — never the user DB.** `data-test/entropia.sqlite` is
  reference-only. Fixtures are built by `data-raw/make_fixtures.R` into
  `tests/testthat/fixtures/` (generated at build time, gitignored artifacts):
  - `mini.sqlite` — minimal core schema (collections/items/assets) for unit tests.
  - `full.sqlite` — complete post-0029 schema (all 29 migrations + sync tables +
    triggers) for integration tests.
  - `legacy-pre0019.sqlite` — variant without `llm_results.target_type`.
  - `legacy-seconds.sqlite` — entities/triples with seconds timestamps.
  - `unknown-version.sqlite` — a future migration name (newer than manifest).
  - `corrupt.sqlite` / `notsqlite.txt` — error-path fixtures.
  - Each fixture ships a small, deterministic dataset (3-5 rows per table).
- **Coverage by concern**: unit (helpers, datetime guards, JSON parsing, marker
  stripping), integration (lazy query correctness, corpus joins, FTS search),
  transactions/write stubs (error classes), schema compat (all policies × all
  fixture variants), error messages (cli snapshot), regression (golden files
  for generated SQL where stable), viz (vdiffr), performance smoke (EXPLAIN
  QUERY PLAN on hot paths).
- **Determinism**: fixtures rebuilt from scripts, not snapshotted by hand.

## Documentation

- roxygen2 on every exported function; executable examples that run against a
  fixture via `\dontrun`-free helper (examples use generated in-memory DBs).
- README with a 10-line getting-started; NEWS.md; LICENSE (MIT).
- Vignettes (all render in CI):
  1. `connect.Rmd` — connecting to an EntropIA DB (read-only, compat, status).
  2. `corpus.Rmd` — exploring the corpus (collections/items/assets/pages).
  3. `text.Rmd` — extracting texts and metadata (OCR, transcriptions, markers).
  4. `dplyr.Rmd` — lazy queries with dplyr/dbplyr on accessors.
  5. `datasets.Rmd` — building reproducible analysis datasets.
  6. `analysis.Rmd` — a complete reproducible analysis (temporal/entities/topics).
  7. `administration.Rmd` — safe data administration (v2 write design + safety).
- pkgdown site with reference index grouped by the 10 API capabilities.

## CI & Quality

- GitHub Actions (r-lib/actions):
  - `R-CMD-check.yaml`: matrix `{os: [ubuntu-latest, windows-latest, macos-latest],
    r: [release, oldrel, devel]}`; runs examples, vignettes, tests.
  - `lint.yaml`: lintr (tidyverse config, adjusted).
  - `style.yaml`: styler check (verification only, not auto-commit).
  - `coverage.yaml`: covr → codecov (gate: ≥ 80% on core modules).
  - `pkgdown.yaml`: build + deploy site on main.
  - `spelling.yaml`: spelling check on docs/vignettes.
- Target: `R CMD check` → **0 errors, 0 warnings**, no avoidable notes on all
  three OSes. Local gate: `devtools::check()` before each phase merge.
- Minimum R: **≥ 4.1** (tidyverse floor; user has 4.0.3–4.5.2 installed — see
  Risks). CI tests release/oldrel/devel.

## Risks & Pending Decisions

| # | Risk / decision | Mitigation / default |
| --- | --- | --- |
| 1 | `entropiaR` name may collide on CRAN/GitHub | Fallback `entropiar`; check before release task. Pending: user confirm at release. |
| 2 | **R not on PATH** (verified: `Rscript` absent; R 4.0.3–4.5.2 in `C:\Program Files\R`) | Plan execution must add R to PATH or call full paths; CI uses r-lib/actions (no local R needed). |
| 3 | dbplyr/FTS5 `MATCH` translation | `entropia_search` builds the MATCH via `dbQuoteString` + `sql()`; unit-tested injection-safety. |
| 4 | RSQLite bundled SQLite version / FTS5 availability | RSQLite ≥ 2.3 bundles FTS5; verified in a task. |
| 5 | WAL sidecars while EntropIA is live | Read-only open + documented `entropia_copy`; `entropia_error_locked` action text. |
| 6 | Mixed timestamp units drift further | `datetime_auto` guard + manifest re-check; new columns with unknown units warn. |
| 7 | Unknown future schema | `warn` policy default; manifest update is the release procedure. |
| 8 | Windows-specific path/encoding in `assets.path` | Strings as-is (UTF-8); document that paths are app-local storage. |
| 9 | Minimum R version | Default ≥ 4.1; confirm during bootstrap task. |
| 10 | Analysis layer "experimental" badge | lifecycle `experimental`; stable in v2. |

## Implementation Steps

Order is dependency-driven. `[x]` marks completion; ➕ for newly discovered
tasks; ⚠️ for blockers. Each task ends with its tests passing before the next
starts. Parallelizable groups noted per phase.

### Phase 0 — Bootstrap (must precede everything)

### Task 1: Scaffold the package skeleton
- [x] run `usethis::create_package(".", open = FALSE)` (or manual equivalent) to scaffold DESCRIPTION/NAMESPACE/R at repo root; confirm it does not clobber `data-test/`, `.atl/`, `.gitignore` (manual equivalent used; `data-test/entropia.sqlite`, `.atl/`, `docs/` verified intact)
- [x] write DESCRIPTION: Package `entropiaR`, Title/Description, `License: MIT + file LICENSE`, Imports/Suggests per Architecture, `RoxygenNote`, `Config/testthat/edition: 3`, `Depends: R (>= 4.1)`
- [x] add LICENSE + LICENSE.md (MIT, user as copyright holder); add `.Rbuildignore` entries (docs/, data-test/, .atl/, .github unless wanted in build)
- [x] extend `.gitignore` (R outputs: `.Rproj.user`, `*.Rcheck`, `renv/` if used)
- [x] write tests: `tests/testthat.R`, empty `testthat/` dir, `helper-fixtures.R` skeleton — run `devtools::test()` (green; testthat 3e aborts with zero test files, so a minimal scaffold smoke test `test-scaffold.R` is included)
- **Acceptance:** `devtools::load_all()` succeeds; `R CMD build` produces a valid tarball; package name `entropiaR` confirmed available (check CRAN + GitHub).
  - Verified 2026-08-06 with R 4.5.2: `load_all()` OK, `devtools::test()` 1 file green, `R CMD build` → `entropiaR_0.0.0.9000.tar.gz` with expected contents. Name check: no `entropiaR` on CRAN (404); GitHub has only `Snikerso/EntropiaR` (2019 entropy-calculation scripts, not a package) — Risk 1 still pending user confirm at release.

### Task 2: R environment + local check gate
- [x] document and verify R invocation for the local machine (add `C:\Program Files\R\R-4.5.2\bin` guidance in README dev section or `renv` bootstrap)
- [x] install dev deps (devtools, roxygen2, testthat, usethis, lintr, styler, covr)
- [x] create `.github/workflows/R-CMD-check.yaml` (r-lib/actions, 3-OS × release matrix, vignettes + examples on)
- [x] create `.github/workflows/lint.yaml` + `style.yaml` (lintr tidyverse config committed as `.lintr`)
- [x] write tests: no R code in v1 — verify CI workflow *syntax* only (dry-run of actionlint or manual review) (actionlint unavailable; all 3 workflows validated via `yaml::read_yaml()` parse)
- **Acceptance:** `devtools::check()` runs end-to-end with 0 errors on the empty package; workflow files parse.
  - Verified 2026-08-06 with R 4.5.2: `devtools::check()` → 0 errors | 0 warnings | 2 notes (env clock note; "Imports not imported from" — expected for the empty scaffold, resolves as code lands). lintr 3.4.0 / styler 1.11.0 / covr 3.6.5 installed.

### Task 3: Fixture infrastructure
- [x] write `data-raw/make_fixtures.R` generating the 6 fixture DBs (mini, full, legacy-pre0019, legacy-seconds, unknown-version, corrupt) from embedded DDL strings (source: `runner.ts` migrations, distilled — see Context) (also emits `notsqlite.txt`; DDL distilled from `runner.ts` MIGRATIONS + `LAYOUTS_DDL`, `sync/schema.rs`, `sync/capture.rs` trigger templates, and the Rust runtime repairs `app_settings`/`rag_asset_embedding_state`)
- [x] fixtures written to `tests/testthat/fixtures/` with deterministic tiny datasets (3–5 rows/table, one collection, familiar values) (all timestamps derive from a fixed epoch `1768478400`/2026-01-15; embeddings are real 4-dim little-endian f32 BLOBs; every DB VACUUMed)
- [x] add `helper-fixtures.R`: `ent_fixture(name)` returning temp copy (so tests never mutate originals), `ent_connect_fixture(name)` (`ent_connect_fixture` prefers `entropia_connect()` once Task 4 lands, falling back to a read-only DBI connection until then)
- [x] write tests: every fixture connects and reports expected `_migrations` version; `legacy-*` variants assert their distinguishing columns exist/absent (`test-fixtures.R`: version per fixture, 48 sync + 33 activity triggers, `target_type` present/absent, seconds-vs-ms magnitude, corrupt/notsqlite unreadable, isolated writable copy)
- [x] run tests — must pass before Task 4 (`devtools::test()` green; `devtools::check()` 0 errors / 0 warnings / 2 acceptable notes)
- **Acceptance:** `make_fixtures.R` is reproducible (delete + rerun → identical); fixtures never touch `data-test/entropia.sqlite`.
  - Verified 2026-08-06 with R 4.5.2 / RSQLite 2.4.3 (SQLite 3.50.4, FTS5 contentless + regular confirmed): delete + rerun produced byte-identical SHA-256 for all artifacts; read-only open refused writes and left `full.sqlite` unchanged; `data-test/` untouched. Packaging fix so fixtures reach `R CMD check`: removed `tests/testthat/fixtures` from `.Rbuildignore` (they are bundled when present) and added a `Generate test fixtures` step to `R-CMD-check.yaml` (fixtures stay gitignored, regenerated in CI).

### Phase 1 — Connection & schema core (after 1–3; tasks 4–8 serial)

### Task 4: entropia_connect read-only + S3 class
- [x] implement `entropia_connect()`: DBI connect with `flags = SQLITE_RO_V2`, `PRAGMA query_only = ON`, class `c("entropia_conn", class(con))`, attributes `path/mode/schema_version/content_hash`; `path = ":memory:"` support (RSQLite 2.4.3 exposes `SQLITE_RO`, not `SQLITE_RO_V2` — used `SQLITE_RO` + `PRAGMA query_only = ON`; connection typed as an S4 subclass `entropia_conn < SQLiteConnection` because prepending a plain S3 class breaks S4 dispatch on DBI generics; attributes verified on the real DB)
- [x] implement `entropia_disconnect()`, `print.entropia_conn()`, `summary.entropia_conn()`, `format.entropia_conn()`, `dbIsValid.entropia_conn()`, `collect.entropia_conn()` (guidance error) (`dbIsValid` works via inherited SQLiteConnection S4 method — reports closed state; `collect()` errors with `entropia_error_unsupported` + guidance)
- [x] implement `entropia_copy()` (WAL-aware: copy `-wal`/`-shm` too when present, via `PRAGMA wal_checkpoint` best-effort or file copy + reopen) (implemented via SQLite `VACUUM INTO` — reads through live `-wal`/`-shm`, emits a single self-contained snapshot; verified with sidecars present)
- [x] write tests: read-only enforced (write attempt errors even with `write = FALSE`), `:memory:` works, class/methods behave, disconnect idempotent, copy works with and without sidecars
- [x] write tests: error paths — missing file (`entropia_error_not_found`), non-SQLite file (`entropia_error_not_sqlite`), locked DB simulation
- [x] run tests — must pass before Task 5 (86 pass, 0 fail; `devtools::check()` 0 errors / 0 warnings / 2 notes — the two known baseline notes)
- **Acceptance:** opening the real `data-test/entropia.sqlite` read-only succeeds and `summary()` renders; a `dbWriteTable` attempt fails cleanly. (Verified 2026-08-06 on the 29 MB reference DB: `schema_version = 0029_rag_chunks`, `summary()` renders, `dbWriteTable` → "attempt to write a readonly database".)

### Task 5: Schema introspection + column contract
- [x] implement internal `ent_current_version(con)` (MAX `_migrations.name`) and `ent_tables(con)` / `ent_columns(con, table)` via `PRAGMA` (`ent_current_version` carried from Task 4's `R/utils.R`; `ent_tables`/`ent_columns` added in `R/schema.R` via `sqlite_master` + `PRAGMA table_xinfo`, FTS shadow tables + `sqlite_*` excluded, generated columns included, `entropia_error_table_missing` for unknown tables)
- [x] implement `entropia_schema_version()`, `entropia_schema_info()` (tables + columns + contract types) (exported; `schema_info` merges live PRAGMA with the manifest contract, `source` = `manifest`/`schema`, column-level `min_version` overrides table-level)
- [x] author `inst/schemas/manifest.json`: full column contract for all 20+ readable tables per the type map in Technical Details, tagged min-migration (26 tables, generated reproducibly by `data-raw/make_manifest.R` from the full fixture + declared contract maps; `manifest_version: 1`, `schema_head: 0029_rag_chunks`, per-column `type`/`required`/`contract`/`values`, migration-tagged `min_version`, repair/sync tables carry no migration)
- [x] implement manifest loader `ent_manifest()` with live `PRAGMA table_info` re-check (loader reads `inst/schemas/manifest.json`; `ent_schema_gaps()` re-checks every manifest column against live `PRAGMA table_xinfo` and flags expected-vs-not with version gating — the raw material for Task 6)
- [x] write tests: version detection on each fixture; manifest covers every fixture table; missing-column detection on legacy variants (`test-schema.R`: per-fixture version, `ent_tables` excludes sqlite_/FTS shadows, generated `search_text` visible, manifest covers all accessor tables, contract types spot-checked, legacy-pre0019 target_type/manual_* gaps with `expected = FALSE`, scratch-DB genuine required-column gap with `expected = TRUE`)
- [x] run tests — must pass before Task 6 (190 pass, 0 fail; lintr clean on all new files; `devtools::check()` 0 errors / 0 warnings / 1 note — the known unused-Imports baseline, resolves as later tasks land)
- **Acceptance:** `entropia_schema_info(entropia_connect("data-test/entropia.sqlite"))` lists every table in the Context with correct types. (Verified 2026-08-06 on the 29 MB reference DB: 30 tables, all Context tables present, `entities.created_at`→`datetime_auto`, `items.metadata`→`json`, `vec_assets.embedding`→`blob_f32`, `collections.created_at`→`datetime_ms`; `ent_schema_gaps()` = 0.)

### Task 6: Compatibility layer + policies
- [x] implement `entropia_schema_compat(con)` returning `known/unknown/older/newer` + required-column check
- [x] wire `options(entropiaR.schema_policy = "warn"|"error"|"allow")` into `entropia_connect(validate = TRUE)`
- [x] implement versioned SQL selector `ent_sql(version, id)` with `R/sql/` fragments (embedded in `R/sql.R` as a fragment registry instead of `.sql` files under `R/sql/` — non-R files in `R/` are not shipped in installed packages, so file-based fragments would break after install; the registry keeps the plan's version-selection design)
- [x] write tests: unknown-version fixture → warn by default, error under `"error"`, silent under `"allow"`; missing required column → error; missing optional column → warn+proceed
- [x] write tests: policy option scoping (withr::with_options), messages contain actionable text (snapshot via testthat snapshots)
- [x] run tests — must pass before Task 7 (54 compat tests + full suite green; `devtools::check()` 0 errors / 0 warnings / 2 known baseline notes; lint-clean apart from the pre-existing cross-file `object_usage` artifact on this machine)
- **Acceptance:** every policy × fixture pair behaves per the table in Robustness. (Verified 2026-08-06: `entropia_schema_compat` classifies full/legacy-seconds as `known`, unknown-version as `newer`, mini/legacy-pre0019 as `older`, `:memory:` as `unknown`; policy matrix warn/error/allow × newer/older/missing-required/missing-optional all behave per the Robustness table, incl. `quiet = TRUE` and an `allow` escape hatch for missing-required columns.)

### Task 7: Diagnostics — validate, status, orphans groundwork
- [x] implement `entropia_validate()`: core-table presence, required-column presence, per-table row counts, empty-DB detection, `EXPLAIN`-free structural checks (findings tibble with `severity`/`kind`/`table`/`column`/`message`; `row_counts` + `schema_version` attributes; version-gated so older-but-complete schemas report nothing; `unreadable` error finding for corrupt files; never raises `table_missing`/`column_missing` — those stay accessor classes)
- [x] implement `entropia_status()`: path, mode, schema version, top row counts, sync freshness from `sync_meta.last_sync_at`, WAL sidecar presence (S3 `entropia_status` list + `print.entropia_status`; sync_meta read as key/value, last_sync_at ms→POSIXct; journal_mode + `-wal`/`-shm` sidecar detection)
- [x] write tests: validate on healthy vs corrupt vs empty fixtures; status fields correct on mini/full fixtures (`test-validate.R`, 60 assertions: healthy fixtures 0 findings, mini tolerated with warnings, missing core table / required column as error findings, empty DB warning, corrupt unreadable, no-tables DB, closed-connection rejection, WAL sidecars, raw DBI path fallback, print output)
- [x] write tests: error classes stable (`entropia_error_table_missing` from `ent_columns`, `entropia_error_column_missing` from new `ent_require_columns` primitive, while validate reports findings instead of raising)
- [x] run tests — must pass before Task 8 (320 pass, 0 fail; lint-clean apart from the known cross-file `object_usage` local artifact; `devtools::check()` 0 errors / 0 warnings / 1 baseline note)
- **Acceptance:** `entropia_validate(con)` on the real test DB returns a useful findings tibble with zero false "broken" reports on healthy tables. (Verified 2026-08-06 on the 29 MB reference DB: 1 warning — `rag_asset_embedding_state`, a Rust repair table the app creates lazily, absent — zero errors; `entropia_status` reports path/mode/`0029_rag_chunks`/row counts/sync `2026-08-04 03:23:25`/journal `wal`/`-wal` sidecar present.)

### Task 8: sync-metadata surface
- [ ] implement `entropia_sync_info(con)`: whitelisted `sync_meta` keys as a tibble (device_id, account_email, server_url, last_sync_at→POSIXct, server_epoch, triggers_version, capture_enabled)
- [ ] implement `entropia_sync_versions(con)` (tbl on `sync_row_versions`) and `entropia_conflicts(con)` (tbl on `sync_conflicts`, `reason` documented)
- [ ] write tests: sync_info values match fixture; sync_versions lazy join test; conflicts reason parsing
- [ ] write tests: `app_settings` NOT surfaced raw (secret keys excluded) — whitelist assertion
- [ ] run tests — must pass before Task 9
- **Acceptance:** on the real DB, `entropia_sync_info()` shows account email + last_sync_at without exposing secrets.

### Phase 2 — Entity access (after 5; tasks 9–13, partially parallel)

### Task 9: Core accessors (collections, items, assets)
- [ ] implement `entropia_collections()`, `entropia_items()`, `entropia_assets()` returning `tbl_sql` on raw tables
- [ ] ensure `entropia_assets()` exposes `parent_asset_id`/`page_number` (PDF pages) and never selects BLOBs
- [ ] write tests: each accessor is lazy (`class` includes `tbl_sql`), columns match the manifest, `nrow` requires `collect`
- [ ] write tests: PDF page parent/child join on full fixture (partial UNIQUE respected)
- [ ] run tests — must pass before Task 10
- **Acceptance:** `entropia_items(con) %>% filter(collection_id == X) %>% collect()` returns expected rows (SQL pushed down, verified via `dbplyr::sql_render`).

### Task 10: Text accessors (extractions, transcriptions, layouts)
- [ ] implement `entropia_extractions()`, `entropia_transcriptions()`, `entropia_layouts()`
- [ ] write tests: deterministic ID formats (`ext-*`, `trx-*`, `lay-*`) derivable from asset_id; UNIQUE(asset_id) reflected
- [ ] write tests: JSON columns recognized by `entropia_collect` (segments → list-column of `{start_ms,end_ms,text}`)
- [ ] run tests — must pass before Task 11
- **Acceptance:** extractions/transcriptions/layouts join 1:1 to assets on full fixture.

### Task 11: Research accessors (entities, triples, topics, notes, annotations)
- [ ] implement `entropia_entities()` with `include_deleted`/`min_confidence`; soft-delete filter `source != 'manual_deleted'` by default
- [ ] implement `entropia_triples()`, `entropia_topics()`, `entropia_item_topics()`, `entropia_notes()`, `entropia_annotations()`
- [ ] write tests: soft-delete default vs include; `entity_type` values; topics UPPERCASE normalization documented (not re-normalized by us)
- [ ] write tests: nullable `asset_id` semantics (item-level rows) exposed as NA
- [ ] run tests — must pass before Task 12
- **Acceptance:** 1339 entities on the real DB collapse correctly with soft-deleted excluded.

### Task 12: AI/RAG accessors (llm_results, conversations, embeddings, chunks, search_index)
- [ ] implement `entropia_llm_results()` (target_type/job_type filters, `llr-*` id format documented), `entropia_rag_conversations()`, `entropia_rag_messages()`
- [ ] implement `entropia_embeddings()` / `entropia_chunks()` with `with_vector` BLOB opt-in; `entropia_search_index()` (raw contentless)
- [ ] write tests: llm_results id parsing; sources JSON → list-column; BLOB not selected by default (`with_vector = FALSE` → no `embedding` col)
- [ ] write tests: `entropia_chunks()` chunking contract values surfaced (chunking_contract, embedding_model, dimensions)
- [ ] run tests — must pass before Task 13
- **Acceptance:** `entropia_chunks(con)` on real DB returns 1648 rows on collect with no BLOB column by default.

### Task 13: entropia_collect + datetime/JSON/BLOB typing
- [ ] implement `entropia_collect()` applying the column contract: datetime cols → POSIXct (ms / `datetime_auto` guard), JSON TEXT → list-columns via jsonlite, BLOB → raw passthrough
- [ ] implement `entropia_datetime()`, `entropia_datetime_s()`, `entropia_datetime_auto()` helpers
- [ ] write tests: ms→POSIXct, seconds→POSIXct, auto-guard on both magnitudes, ISO-8601 inside metadata parsed to POSIXct
- [ ] write tests: JSON parse shapes (metadata object, segments array, sources array, result text) incl. malformed JSON → warning + NA
- [ ] run tests — must pass before Task 14
- **Acceptance:** `entropia_collect(entropia_items(con))` yields `created_at` as POSIXct with correct dates on both ms and seconds fixtures.

### Task 14: entropia_search (FTS5)
- [ ] implement `entropia_search()` with `index = "items"` (rowid join to items) and `"chunks"` (chunk_id join), `limit`, injection-safe `dbQuoteString` + `MATCH`
- [ ] write tests: known-term search returns expected rows on full fixture; multi-word queries; empty query errors; injection attempt (`'; DROP TABLE --`) is inert
- [ ] write tests: contentless join correctness (items text is NOT NULL where matched)
- [ ] run tests — must pass before Task 15
- **Acceptance:** searching "huelga" on the real DB returns items with matched extracted text.

### Phase 3 — Domain layer (after 9–14; tasks 15–19 serial)

### Task 15: entropia_text
- [ ] implement `entropia_text()`: `source ∈ extraction|transcription|auto` (auto = extraction else transcription, in SQL), `strip_markers = TRUE` removes `![](page=n,bbox=...)`
- [ ] write tests: auto-selection per asset both present/one-present/neither; marker stripping regex on fixture text; empty text handling
- [ ] run tests — must pass before Task 16
- **Acceptance:** on real DB, every asset with an extraction gets its text; 27 marker-bearing extractions strip cleanly.

### Task 16: entropia_corpus
- [ ] implement `entropia_corpus()`: lazy `items ⋈ collections ⋈ assets ⋈ text` with `collections`/`asset_types` filters, `page_assets` toggle, `include_deleted`
- [ ] implement `entropia_metadata()`: `items.metadata` parsed to tidy rows (original_name/path/imported_at + list-columns)
- [ ] write tests: corpus join cardinality on full fixture (no fan-out from layouts/extractions dupes); filters push down to SQL (`sql_render` assertion)
- [ ] write tests: metadata parse incl. missing metadata → NA row; imported_at ISO → POSIXct
- [ ] run tests — must pass before Task 17
- **Acceptance:** `entropia_corpus(con, collections = "X")` on real DB returns one row per asset with text, metadata, collection name — SQL-rendered join, no BLOB.

### Task 17: Corpus quality helpers
- [ ] implement `entropia_ocr_coverage()`, `entropia_metadata_coverage()`, `entropia_corpus_quality()` per the API
- [ ] write tests: coverage math on fixtures with known gaps (asset without extraction, item without metadata, empty extraction text)
- [ ] run tests — must pass before Task 18
- **Acceptance:** on real DB, `entropia_corpus_quality()` reports image/audio/pdf coverage realistically (e.g. 258/2477 extractions).

### Task 18: entropia_orphans + relationship integrity
- [ ] implement `entropia_orphans()` detecting broken refs across all conceptual FKs (items→collections, assets→items, text→assets, entities/triples→items, llm_results→target, rag_messages→conversations)
- [ ] write tests: synthetic broken refs inserted into a fixture copy → detected with correct `kind`/`table`/`id`; clean fixture → zero findings
- [ ] run tests — must pass before Task 19
- **Acceptance:** on real DB, orphans finds only genuinely broken rows (audit each reported kind manually once).

### Task 19: Conversations + entity/triple relations
- [ ] implement `entropia_conversation()` (ordered messages + parsed sources), `entropia_entity_relations()` (triples with context), `entropia_reconstruct_analysis()` (llm_results joined back to target)
- [ ] write tests: conversation ordering by sort_index; sources parse; reconstruct joins across target_type (asset/item/collection)
- [ ] run tests — must pass before Task 20
- **Acceptance:** on real DB, one conversation reconstructs with citations; llm_results reconstruct against assets.

### Phase 4 — Analysis & visualization (after 16; tasks 20–23; 20–21 parallel, then 22–23)

### Task 20: Temporal + length analysis
- [ ] implement `entropia_temporal_profile()`, `entropia_document_lengths()` on tibbles
- [ ] write tests: known counts on fixture; date_var typing; NA handling
- [ ] run tests — must pass before Task 22
- **Acceptance:** on real DB, temporal profile by month renders from `created_at` (ms).

### Task 21: Entity/topic frequency + collection comparison
- [ ] implement `entropia_entity_frequency()`, `entropia_topic_frequency()`, `entropia_compare_collections()`
- [ ] write tests: frequency math on fixtures; grouping by entity_type/collection
- [ ] run tests — must pass before Task 22
- **Acceptance:** on real DB, top entities by type match a manual SQL spot-check.

### Task 22: entropia_analysis_dataset + provenance
- [ ] implement `entropia_analysis_dataset()` (corpus → filters → collect → class `entropia_dataset` + `entropia_prov` attributes)
- [ ] implement `entropia_provenance()` / `entropia_write_provenance()` (JSON sidecar)
- [ ] write tests: provenance fields correct (schema version, content hash, captured filters, package version); JSON round-trip; dataset class methods (print/glimpse/as_tibble)
- [ ] run tests — must pass before Task 23
- **Acceptance:** building a dataset twice yields identical content hash and reproducible provenance.

### Task 23: Visualization helpers
- [ ] implement `entropia_plot_coverage()`, `entropia_plot_temporal()`, `entropia_plot_entities()` (Suggests ggplot2, `requireNamespace` guard, return `ggplot`)
- [ ] write tests: each returns a `ggplot` object (class assertion); data mapping correct; vdiffr snapshot on fixture data
- [ ] run tests — must pass before Task 24
- **Acceptance:** plots render and remain user-extensible (`+ labs(...)`).

### Phase 5 — Export & stubs (after 13; tasks 24–25 parallel)

### Task 24: entropia_export (csv/tsv/json/rds + streaming)
- [ ] implement `entropia_export()` with csv/tsv/json/rds; deterministic ordering; chunked streaming for lazy inputs
- [ ] write tests: round-trips (export → import → identical); streamed vs collected equivalence on larger fixture; format validation errors
- [ ] run tests — must pass before Task 25
- **Acceptance:** exporting the corpus to CSV on the real DB streams without a full collect spike.

### Task 25: parquet/arrow + write stubs
- [ ] implement `format = "parquet"/"arrow"` behind `requireNamespace("arrow")` with clear missing-dep error
- [ ] implement v2 write stubs: `entropia_insert/update/upsert/delete` abort with `entropia_error_write_disabled` + documented v2 guidance; `entropia_connect(write = TRUE)` errors
- [ ] write tests: parquet round-trip when arrow present (skip otherwise); every stub errors with correct class and actionable message
- [ ] run tests — must pass before Task 26
- **Acceptance:** `R CMD check` passes with arrow installed AND without (Suggests discipline).

### Phase 6 — Docs & polish (after 16; tasks 26–28)

### Task 26: README + pkgdown + API reference
- [ ] write README (10-line getting-started with real-DB example), NEWS.md initial entry, `_pkgdown.yml` with grouped reference index
- [ ] roxygen2 docs + runnable examples on every exported function (in-memory fixture examples)
- [ ] write tests: examples run in `R CMD check` (implicit); pkgdown builds locally
- [ ] run tests — must pass before Task 27
- **Acceptance:** `pkgdown::build_site()` succeeds; every exported fn documented with a runnable example.

### Task 27: Vignettes (7)
- [ ] write `connect.Rmd`, `corpus.Rmd`, `text.Rmd`, `dplyr.Rmd`, `datasets.Rmd`, `analysis.Rmd`, `administration.Rmd` per Documentation
- [ ] vignettes knit cleanly against fixtures (never the user DB)
- [ ] write tests: vignette build in check (implicit); spelling pass on vignettes
- [ ] run tests — must pass before Task 28
- **Acceptance:** all 7 vignettes render in CI; the analysis vignette is a complete reproducible workflow ending in a provenance-stamped dataset.

### Task 28: Lifecycle + error message audit
- [ ] add lifecycle badges (experimental on analysis layer); `lifecycle::deprecate_warn` scaffolding documented
- [ ] audit every exported error/warning for cli formatting + class + actionable message; snapshot tests for key messages
- [ ] write tests: message snapshots; badge presence in docs
- [ ] run tests — must pass before Task 29
- **Acceptance:** no bare `stop()`/`warning()` without class+cli in exported code (`grep` gate in CI task).

### Phase 7 — CI & Definition of Done (after 26; tasks 29–31)

### Task 29: CI matrix + lint + style gates
- [ ] finalize `R-CMD-check.yaml` (3-OS × release/oldrel/devel), `lint.yaml`, `style.yaml` (verification-only), coverage gate
- [ ] add `spelling.yaml`; add a `grep`-gate job (no `stop(`/`warning(` without cli/class in `R/`)
- [ ] write tests: CI is green end-to-end on a pushed branch (verify once)
- [ ] run tests: full suite + `devtools::check()` — must pass before Task 30
- **Acceptance:** GitHub Actions green on all 3 OS; coverage ≥ 80% on `connect.R`, `schema.R`, `corpus.R`, `collect.R`.

### Task 30: R CMD check clean + performance pass
- [ ] resolve every warning/note; document unavoidable notes in NEWS
- [ ] performance pass: `EXPLAIN QUERY PLAN` on corpus/search/entity-join; fix any table scans on hot paths; add a smoke test asserting no full-scan on the corpus join
- [ ] write tests: performance smoke test (EXPLAIN-based); full regression run
- [ ] run tests — must pass before Task 31
- **Acceptance:** `R CMD check` → 0 errors, 0 warnings, no avoidable notes on all 3 OS; corpus join plan uses `idx_*` indexes.

### Task 31: Definition of Done gate
- [ ] verify all Overview requirements implemented (audit against the 10 API capabilities)
- [ ] verify edge cases handled (empty DB, NULL, unknown version, corrupt file, locked DB)
- [ ] run full test suite on all fixtures + real-DB smoke (assert-only, no fixture usage)
- [ ] verify coverage meets ≥ 80% standard on core modules
- [ ] verify docs complete (README, NEWS, 7 vignettes, pkgdown, every public fn documented)
- [ ] verify CI green on a clean branch; write final acceptance report into this plan (➕)
- **Acceptance:** Definition of Done below fully satisfied.

## Technical Details

### Column type map (manifest source; `datetime_auto` = magnitude guard)

| Table | Typed columns |
| --- | --- |
| collections | created_at, updated_at → datetime_ms |
| items | created_at, updated_at → datetime_ms; metadata → json |
| assets | created_at → datetime_ms; size → int; type → enum |
| extractions | created_at → datetime_ms; confidence → dbl |
| transcriptions | created_at → datetime_ms; segments → json; duration_ms → int; confidence → dbl |
| layouts | created_at → datetime_ms; regions, blocks → json; image_width/height → int |
| notes | created_at, updated_at → datetime_ms |
| annotations | created_at, updated_at → datetime_ms; x/y/width/height → dbl; page → int; kind → enum |
| entities | created_at → **datetime_auto**; confidence → dbl; offsets → int; entity_type → enum; geo cols → dbl; geo_status → enum |
| triples | created_at → **datetime_auto** |
| topics, item_topics | created_at → datetime_ms |
| llm_results | created_at → datetime_ms; result → json; target_type → enum |
| rag_conversations | created_at, updated_at → datetime_ms |
| rag_messages | created_at → datetime_ms; sources → json; role → enum |
| vec_assets | embedding → blob_f32; dimensions → int |
| rag_chunks | embedding → blob_f32; start/end_char, chunk_ordinal, dimensions → int; source_kind → enum |
| sync_meta | last_sync_at → datetime_ms (whitelisted keys) |
| sync_conflicts | created_at → datetime_ms; reason → enum |

### Datetime strategy
- ms: `as.POSIXct(x / 1000, origin = "1970-01-01", tz = "UTC")`.
- `datetime_auto`: `ifelse(x < 1e12, x, x / 1000)` then POSIXct (the 0019 guard).
- ISO-8601 inside JSON: `lubridate::as_datetime` equivalent via `as.POSIXct(..., format = "%Y-%m-%dT%H:%M:%OSZ", tz = "UTC")` (base R, no lubridate dependency in core).

### FTS5 search construction
```r
q <- DBI::dbQuoteString(con, query)          # injection-safe literal
tbl(db, sql("SELECT ... FROM fts_items WHERE fts_items MATCH ", q))
```
`items` index: `JOIN items i ON i.rowid = fts_items.rowid` (contentless rule).
`chunks` index: `JOIN rag_chunks c ON c.id = rag_chunks_fts.chunk_id`.

### Write stub signatures (v2 contract, v1 errors)
```r
entropia_insert(con, table, data, dry_run = TRUE)
entropia_update(con, table, data, by, dry_run = TRUE)
entropia_upsert(con, table, data, by, dry_run = TRUE)
entropia_delete(con, table, filter, all = FALSE, confirm = FALSE)
```

### Processing flow: entropia_corpus
1. `tbl(con, "items")` → `left_join(collections)` → `left_join(assets)`.
2. Append text: `COALESCE` extraction/transcription via subquery per
   `source` mode (single SQL pass, no R loops).
3. Apply `collections`/`asset_types`/`include_deleted` filters in SQL.
4. Return `tbl_sql`; `entropia_collect()` applies the contract.

## Post-Completion

*No checkboxes — external/manual items.*

**Manual verification:**
- Open the real `data-test/entropia.sqlite` while EntropIA Lite is running
  (WAL active) — read-only connect, status, corpus, search, export must all work.
- Long-running analysis on the full corpus (2.4k items) — memory stays flat.
- Cross-check `entropia_validate()` findings against the app's own DB browser.

**External system updates:**
- Decide GitHub repo + release for `entropiaR`; run the name-collision check.
- pkgdown site deployment (Netlify/GitHub Pages) after Task 29.
- Optional: propose documenting the schema contract upstream in
  `EntropIA-Pro-Lite/SQLite.md` (the R package formalizes what the app
  informally documents).
- v2: write API implementation (designed in this plan, stubbed in v1).

## Definition of Done (global)

1. `R CMD check` → **0 errors, 0 warnings**, no avoidable notes, on
   ubuntu/windows/macos × release/oldrel/devel.
2. Full testthat 3e suite green on all fixtures (mini, full, 4 legacy/error
   variants); no test uses the user's real database.
3. Coverage ≥ 80% on core modules (connect, schema, corpus, collect).
4. Lintr + styler clean; spelling clean; no bare `stop()`/`warning()` in
   exported code.
5. All 7 vignettes render; every exported function documented with a runnable
   example; pkgdown site builds.
6. Public API surface finalized exactly as designed (no undocumented exports);
   lifecycle policy applied (experimental badges on analysis layer).
7. Read-only safety verified: write attempts fail with
   `entropia_error_write_disabled`; `data-test/entropia.sqlite` byte-identical
   before/after any test run.
8. Reproducibility: `entropia_analysis_dataset()` output carries complete
   provenance; identical inputs → identical datasets.
9. Performance smoke test green: corpus/search/entity joins use indexes
   (EXPLAIN QUERY PLAN), no full collect in hot paths.
10. Final acceptance report appended to this plan and reviewed before ralphex
    moves it to `docs/plans/completed/`.