# make_fixtures.R -- deterministic test-fixture generator for entropiaR
#
# Generates the SQLite fixture databases used by the test suite into
# tests/testthat/fixtures/. These fixtures are tiny, fully deterministic, and
# self-contained: the schema DDL is distilled from the authoritative sources
# (EntropIA-Pro-Lite `packages/store/src/runner.ts` MIGRATIONS + the Rust
# runtime repairs) and the row data is hard-coded. They NEVER read from or
# write to data-test/entropia.sqlite (that file is a reference corpus only).
#
# Regenerate with (from the package root):
#   Rscript data-raw/make_fixtures.R
#
# Fixtures produced:
#   mini.sqlite            minimal core schema (collections/items/assets/notes)
#   full.sqlite            complete post-0029 schema + sync tables + triggers
#   legacy-pre0019.sqlite  llm_results WITHOUT target_type (version 0018)
#   legacy-seconds.sqlite  entities/triples created_at in epoch SECONDS
#   unknown-version.sqlite full schema, _migrations head newer than manifest
#   corrupt.sqlite         SQLite magic header followed by garbage bytes
#   notsqlite.txt          plain-text file (not a SQLite database)
#
# Design notes:
#   - All timestamps derive from a single hard-coded epoch so repeated runs are
#     byte-for-byte reproducible (no Date.now()/Sys.time() anywhere).
#   - Every DB is VACUUMed at the end to normalise page layout.
#   - Embedding BLOBs are real little-endian f32 vectors (4 dims, 16 bytes) so
#     downstream blob_f32 decoding has genuine bytes to work with.

suppressMessages({
  library(DBI)
  library(RSQLite)
})

# ---------------------------------------------------------------------------
# Locations
# ---------------------------------------------------------------------------
# Resolve package root relative to this script so the generator works no matter
# which working directory it is invoked from.
script_path <- (function() {
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (length(file_arg) > 0) {
    return(normalizePath(sub("^--file=", "", file_arg[1]), winslash = "/"))
  }
  # Fallback (e.g. sourced interactively): assume cwd is the package root.
  normalizePath(file.path("data-raw", "make_fixtures.R"), winslash = "/")
})()
pkg_root <- normalizePath(dirname(dirname(script_path)), winslash = "/")
out_dir <- file.path(pkg_root, "tests", "testthat", "fixtures")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

# Guard: never touch the reference corpus.
stopifnot(!identical(normalizePath(out_dir, winslash = "/"),
                     normalizePath(file.path(pkg_root, "data-test"), winslash = "/")))

# ---------------------------------------------------------------------------
# Deterministic epoch + ids
# ---------------------------------------------------------------------------
BASE_S <- 1768478400 # 2026-01-15 12:00:00 UTC (epoch seconds)
BASE_MS <- BASE_S * 1000

ms <- function(offset_s) BASE_MS + offset_s * 1000 # helper: ms timestamp
secs <- function(offset_s) BASE_S + offset_s # helper: seconds timestamp

COLL_1 <- "11111111-1111-4111-8111-111111111111"
ITEM_1 <- "22222222-2222-4222-8222-222222222221"
ITEM_2 <- "22222222-2222-4222-8222-222222222222"
ITEM_3 <- "22222222-2222-4222-8222-222222222223"
ASSET_PDF <- "33333333-3333-4333-8333-333333333331"
ASSET_PAGE1 <- "33333333-3333-4333-8333-333333333332"
ASSET_PAGE2 <- "33333333-3333-4333-8333-333333333333"
ASSET_IMG <- "33333333-3333-4333-8333-333333333334"
ASSET_AUDIO <- "33333333-3333-4333-8333-333333333335"
NOTE_1 <- "55555555-5555-4555-8555-555555555551"
NOTE_2 <- "55555555-5555-4555-8555-555555555552"
ANN_1 <- "66666666-6666-4666-8666-666666666661"
ENT_1 <- "77777777-7777-4777-8777-777777777771"
ENT_2 <- "77777777-7777-4777-8777-777777777772"
ENT_3 <- "77777777-7777-4777-8777-777777777773"
ENT_DEL <- "77777777-7777-4777-8777-777777777774"
TRIPLE_1 <- "88888888-8888-4888-8888-888888888881"
TOPIC_1 <- "99999999-9999-4999-8999-999999999991"
TOPIC_2 <- "99999999-9999-4999-8999-999999999992"
IT_1 <- "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1"
IT_2 <- "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2"
CONV_1 <- "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1"
MSG_1 <- "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2"
MSG_2 <- "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb3"
CHUNK_1 <- "ragchk-0000000000000000000000000000000000000000000000000000000000000001"

EXT_PDF <- paste0("ext-", ASSET_PDF)
EXT_PAGE1 <- paste0("ext-", ASSET_PAGE1)
TRX_AUDIO <- paste0("trx-", ASSET_AUDIO)
LAY_PDF <- paste0("lay-", ASSET_PDF)
LLR_1 <- paste0("llr-item-", ITEM_1, "-summary")

# A real little-endian f32 vector (4 dims -> 16 bytes) for embedding BLOBs.
f32_bytes <- function(nums) {
  writeBin(as.numeric(nums), raw(), size = 4L, endian = "little")
}
EMB_VEC <- f32_bytes(c(0.1, -0.2, 0.3, 0.4))

# ---------------------------------------------------------------------------
# Table DDL (final post-0029 shapes unless noted)
# ---------------------------------------------------------------------------
T_MIGRATIONS <- "
CREATE TABLE _migrations (
  id    INTEGER PRIMARY KEY AUTOINCREMENT,
  name  TEXT    NOT NULL UNIQUE,
  applied_at INTEGER NOT NULL
)"

T_COLLECTIONS <- "
CREATE TABLE collections (
  id          TEXT    PRIMARY KEY,
  name        TEXT    NOT NULL,
  description TEXT,
  created_at  INTEGER NOT NULL,
  updated_at  INTEGER NOT NULL
)"

T_ITEMS <- "
CREATE TABLE items (
  id            TEXT    PRIMARY KEY,
  title         TEXT    NOT NULL,
  collection_id TEXT    NOT NULL REFERENCES collections(id),
  metadata      TEXT,
  created_at    INTEGER NOT NULL,
  updated_at    INTEGER NOT NULL,
  search_text   TEXT GENERATED ALWAYS AS (
    COALESCE(title, '') || ' ' || COALESCE(json(metadata), '')
  ) STORED
)"

# assets with page columns (0024). pre-0019 variant drops parent/page + sort.
T_ASSETS <- "
CREATE TABLE assets (
  id         TEXT    PRIMARY KEY,
  item_id    TEXT    NOT NULL REFERENCES items(id),
  path       TEXT    NOT NULL,
  type       TEXT    NOT NULL,
  size       INTEGER,
  created_at INTEGER NOT NULL,
  sort_index INTEGER NOT NULL DEFAULT 0,
  parent_asset_id TEXT REFERENCES assets(id) ON DELETE CASCADE,
  page_number INTEGER
)"
T_ASSETS_PRE0019 <- "
CREATE TABLE assets (
  id         TEXT    PRIMARY KEY,
  item_id    TEXT    NOT NULL REFERENCES items(id),
  path       TEXT    NOT NULL,
  type       TEXT    NOT NULL,
  size       INTEGER,
  created_at INTEGER NOT NULL,
  sort_index INTEGER NOT NULL DEFAULT 0
)"

T_NOTES <- "
CREATE TABLE notes (
  id         TEXT    PRIMARY KEY,
  item_id    TEXT    NOT NULL REFERENCES items(id),
  content    TEXT    NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  asset_id   TEXT
)"

T_EXTRACTIONS <- "
CREATE TABLE extractions (
  id TEXT PRIMARY KEY,
  asset_id TEXT NOT NULL REFERENCES assets(id) ON DELETE CASCADE,
  text_content TEXT NOT NULL,
  method TEXT NOT NULL,
  confidence REAL,
  created_at INTEGER NOT NULL
)"

# entities with geo + manual coords (0011/0026) + asset_id (0014).
T_ENTITIES <- "
CREATE TABLE entities (
  id TEXT PRIMARY KEY NOT NULL,
  item_id TEXT NOT NULL REFERENCES items(id) ON DELETE CASCADE,
  entity_type TEXT NOT NULL CHECK(entity_type IN
    ('person','place','date','institution','organization','misc','custom')),
  value TEXT NOT NULL,
  start_offset INTEGER NOT NULL DEFAULT 0,
  end_offset INTEGER NOT NULL DEFAULT 0,
  confidence REAL NOT NULL DEFAULT 1.0,
  source TEXT,
  model_name TEXT,
  created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
  latitude REAL,
  longitude REAL,
  geo_status TEXT NOT NULL DEFAULT 'pending',
  asset_id TEXT,
  manual_lat REAL,
  manual_lon REAL
)"
# pre-0019 entities: no manual coords (0026 not applied); asset_id present (0014).
T_ENTITIES_PRE0019 <- "
CREATE TABLE entities (
  id TEXT PRIMARY KEY NOT NULL,
  item_id TEXT NOT NULL REFERENCES items(id) ON DELETE CASCADE,
  entity_type TEXT NOT NULL CHECK(entity_type IN
    ('person','place','date','institution','organization','misc','custom')),
  value TEXT NOT NULL,
  start_offset INTEGER NOT NULL DEFAULT 0,
  end_offset INTEGER NOT NULL DEFAULT 0,
  confidence REAL NOT NULL DEFAULT 1.0,
  source TEXT,
  model_name TEXT,
  created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
  latitude REAL,
  longitude REAL,
  geo_status TEXT NOT NULL DEFAULT 'pending',
  asset_id TEXT
)"

T_TRIPLES <- "
CREATE TABLE triples (
  id TEXT PRIMARY KEY NOT NULL,
  item_id TEXT NOT NULL REFERENCES items(id) ON DELETE CASCADE,
  subject TEXT NOT NULL,
  predicate TEXT NOT NULL,
  object TEXT NOT NULL,
  created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
  asset_id TEXT
)"

# annotations with expanded kind (0025). pre-0019 keeps rectangle/underline only.
T_ANNOTATIONS <- "
CREATE TABLE annotations (
  id TEXT PRIMARY KEY NOT NULL,
  asset_id TEXT NOT NULL REFERENCES assets(id) ON DELETE CASCADE,
  page INTEGER NOT NULL DEFAULT 1,
  kind TEXT NOT NULL CHECK(kind IN ('rectangle', 'underline', 'crop', 'erase', 'rotation')),
  color TEXT NOT NULL,
  x REAL NOT NULL,
  y REAL NOT NULL,
  width REAL NOT NULL,
  height REAL NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)"
T_ANNOTATIONS_PRE0019 <- "
CREATE TABLE annotations (
  id TEXT PRIMARY KEY NOT NULL,
  asset_id TEXT NOT NULL REFERENCES assets(id) ON DELETE CASCADE,
  page INTEGER NOT NULL DEFAULT 1,
  kind TEXT NOT NULL CHECK(kind IN ('rectangle', 'underline')),
  color TEXT NOT NULL,
  x REAL NOT NULL,
  y REAL NOT NULL,
  width REAL NOT NULL,
  height REAL NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)"

T_TRANSCRIPTIONS <- "
CREATE TABLE transcriptions (
  id TEXT PRIMARY KEY,
  asset_id TEXT NOT NULL REFERENCES assets(id) ON DELETE CASCADE,
  text_content TEXT NOT NULL,
  language TEXT,
  duration_ms INTEGER,
  model TEXT NOT NULL,
  segments TEXT,
  confidence REAL,
  created_at INTEGER NOT NULL
)"

T_TOPICS <- "
CREATE TABLE topics (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  created_at INTEGER NOT NULL
)"

T_ITEM_TOPICS <- "
CREATE TABLE item_topics (
  id TEXT PRIMARY KEY,
  item_id TEXT NOT NULL REFERENCES items(id) ON DELETE CASCADE,
  topic_id TEXT NOT NULL REFERENCES topics(id) ON DELETE CASCADE,
  created_at INTEGER NOT NULL
)"

# llm_results WITH target_type (post-0019).
T_LLM_RESULTS <- "
CREATE TABLE llm_results (
  id TEXT PRIMARY KEY,
  target_id TEXT NOT NULL,
  target_type TEXT NOT NULL CHECK(target_type IN ('asset', 'item', 'collection', 'unknown')),
  job_type TEXT NOT NULL,
  result TEXT NOT NULL,
  created_at INTEGER NOT NULL
)"
# pre-0019 llm_results: NO target_type (the distinguishing feature).
T_LLM_RESULTS_PRE0019 <- "
CREATE TABLE llm_results (
  id TEXT PRIMARY KEY,
  target_id TEXT NOT NULL,
  job_type TEXT NOT NULL,
  result TEXT NOT NULL,
  created_at INTEGER NOT NULL
)"

# vec_assets with embedding contract (0028). pre-0019 drops those three columns.
T_VEC_ASSETS <- "
CREATE TABLE vec_assets (
  asset_id TEXT PRIMARY KEY,
  item_id TEXT NOT NULL,
  embedding BLOB NOT NULL,
  embedding_model TEXT NOT NULL DEFAULT 'legacy',
  embedding_contract TEXT NOT NULL DEFAULT 'legacy',
  dimensions INTEGER NOT NULL DEFAULT 0
)"
T_VEC_ASSETS_PRE0019 <- "
CREATE TABLE vec_assets (
  asset_id TEXT PRIMARY KEY,
  item_id TEXT NOT NULL,
  embedding BLOB NOT NULL
)"

T_LAYOUTS <- "
CREATE TABLE layouts (
  id TEXT PRIMARY KEY,
  asset_id TEXT NOT NULL REFERENCES assets(id) ON DELETE CASCADE,
  regions TEXT NOT NULL,
  blocks TEXT NOT NULL DEFAULT '[]',
  model TEXT NOT NULL,
  image_width INTEGER NOT NULL,
  image_height INTEGER NOT NULL,
  created_at INTEGER NOT NULL
)"

T_RAG_CONVERSATIONS <- "
CREATE TABLE rag_conversations (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)"

T_RAG_MESSAGES <- "
CREATE TABLE rag_messages (
  id TEXT PRIMARY KEY,
  conversation_id TEXT NOT NULL REFERENCES rag_conversations(id) ON DELETE CASCADE,
  sort_index INTEGER NOT NULL,
  role TEXT NOT NULL CHECK(role IN ('user','assistant')),
  content TEXT NOT NULL,
  sources TEXT,
  model TEXT,
  created_at INTEGER NOT NULL
)"

T_RAG_CHUNKS <- "
CREATE TABLE rag_chunks (
  id TEXT PRIMARY KEY,
  asset_id TEXT NOT NULL REFERENCES assets(id) ON DELETE CASCADE,
  item_id TEXT NOT NULL REFERENCES items(id) ON DELETE CASCADE,
  source_kind TEXT NOT NULL CHECK(source_kind IN ('extraction', 'transcription')),
  source_id TEXT NOT NULL,
  chunk_ordinal INTEGER NOT NULL CHECK(chunk_ordinal >= 0),
  text_content TEXT NOT NULL,
  start_char INTEGER NOT NULL CHECK(start_char >= 0),
  end_char INTEGER NOT NULL CHECK(end_char > start_char),
  source_text_hash TEXT NOT NULL,
  chunking_contract TEXT NOT NULL,
  embedding BLOB NOT NULL,
  embedding_model TEXT NOT NULL,
  embedding_contract TEXT NOT NULL,
  dimensions INTEGER NOT NULL CHECK(dimensions > 0),
  UNIQUE(asset_id, source_kind, source_id, chunk_ordinal)
)"

# Rust runtime-repair tables (present without a _migrations entry).
T_APP_SETTINGS <- "
CREATE TABLE app_settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
)"

T_RAG_EMBEDDING_STATE <- "
CREATE TABLE rag_asset_embedding_state (
  asset_id TEXT PRIMARY KEY,
  item_id TEXT NOT NULL,
  rag_incomplete INTEGER NOT NULL DEFAULT 0,
  failure_count INTEGER NOT NULL DEFAULT 0,
  next_retry_at_ms INTEGER NOT NULL DEFAULT 0,
  last_error TEXT,
  updated_at_ms INTEGER NOT NULL DEFAULT 0
)"

# Virtual FTS5 tables.
V_FTS_ITEMS <- "
CREATE VIRTUAL TABLE fts_items
USING fts5(
  item_id UNINDEXED,
  title,
  metadata,
  extracted_text,
  tokenize='unicode61 remove_diacritics 1',
  content=''
)"

V_RAG_CHUNKS_FTS <- "
CREATE VIRTUAL TABLE rag_chunks_fts USING fts5(
  chunk_id UNINDEXED,
  text_content,
  tokenize = 'unicode61 remove_diacritics 1'
)"

# Sync-engine bookkeeping tables (src-tauri/src/sync/schema.rs).
SYNC_TABLES <- list(
  "CREATE TABLE sync_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)",
  "CREATE TABLE sync_oplog (
     seq INTEGER PRIMARY KEY AUTOINCREMENT,
     table_name TEXT NOT NULL,
     row_id TEXT NOT NULL,
     op TEXT NOT NULL CHECK (op IN ('I','U','D')),
     changed_at INTEGER NOT NULL)",
  "CREATE INDEX idx_sync_oplog_row ON sync_oplog(table_name, row_id)",
  "CREATE TABLE sync_row_versions (
     table_name TEXT NOT NULL,
     row_id TEXT NOT NULL,
     server_seq INTEGER NOT NULL,
     PRIMARY KEY (table_name, row_id))",
  "CREATE TABLE sync_conflicts (
     id TEXT PRIMARY KEY,
     table_name TEXT NOT NULL,
     row_id TEXT NOT NULL,
     reason TEXT NOT NULL,
     loser_payload TEXT,
     winner_summary TEXT,
     created_at INTEGER NOT NULL,
     acknowledged INTEGER NOT NULL DEFAULT 0)",
  "CREATE TABLE sync_pending_rows (
     table_name TEXT NOT NULL,
     row_id TEXT NOT NULL,
     server_seq INTEGER NOT NULL,
     deleted INTEGER NOT NULL,
     changed_at INTEGER NOT NULL,
     device_id TEXT NOT NULL,
     payload TEXT,
     retry_count INTEGER NOT NULL DEFAULT 0,
     parked_schema_head TEXT,
     PRIMARY KEY (table_name, row_id))",
  "CREATE TABLE sync_pending_blobs (
     asset_id TEXT PRIMARY KEY,
     sha256 TEXT NOT NULL,
     rel_path TEXT NOT NULL,
     size INTEGER NOT NULL,
     retry_count INTEGER NOT NULL DEFAULT 0,
     last_error TEXT,
     last_attempt_at INTEGER)",
  "CREATE TABLE sync_pending_fts (item_id TEXT PRIMARY KEY)",
  "CREATE TABLE sync_topic_aliases (remote_id TEXT PRIMARY KEY, local_id TEXT NOT NULL)",
  "CREATE TABLE sync_blob_index (
     asset_id TEXT PRIMARY KEY,
     sha256 TEXT NOT NULL,
     size INTEGER NOT NULL,
     file_mtime_ms INTEGER NOT NULL,
     uploaded INTEGER NOT NULL DEFAULT 0)"
)

# Indexes for the core (non-sync) tables. `target_type` index is gated because
# the pre-0019 variant has no such column.
core_indexes <- function(include_target_type = TRUE) {
  idx <- c(
    "CREATE INDEX idx_items_search ON items(search_text)",
    "CREATE INDEX idx_items_collection ON items(collection_id)",
    "CREATE INDEX idx_assets_item ON assets(item_id)",
    "CREATE INDEX idx_assets_item_sort ON assets(item_id, sort_index)",
    "CREATE INDEX idx_notes_item ON notes(item_id)",
    "CREATE INDEX idx_notes_asset_id ON notes(asset_id)",
    "CREATE INDEX idx_extractions_asset_id ON extractions(asset_id)",
    "CREATE UNIQUE INDEX idx_extractions_asset_id_unique ON extractions(asset_id)",
    "CREATE INDEX idx_entities_item_id ON entities(item_id)",
    "CREATE INDEX idx_entities_type ON entities(entity_type)",
    "CREATE INDEX idx_entities_geo_status ON entities(geo_status)",
    "CREATE INDEX idx_entities_asset_id ON entities(asset_id)",
    "CREATE INDEX triples_item_id_idx ON triples(item_id)",
    "CREATE INDEX idx_triples_asset_id ON triples(asset_id)",
    "CREATE INDEX annotations_asset_id_idx ON annotations(asset_id)",
    "CREATE INDEX annotations_asset_page_idx ON annotations(asset_id, page)",
    "CREATE INDEX idx_transcriptions_asset_id ON transcriptions(asset_id)",
    "CREATE UNIQUE INDEX idx_transcriptions_asset_id_unique ON transcriptions(asset_id)",
    "CREATE INDEX idx_llm_results_target ON llm_results(target_id)",
    "CREATE UNIQUE INDEX idx_item_topics_item_topic ON item_topics(item_id, topic_id)",
    "CREATE INDEX idx_item_topics_topic_id ON item_topics(topic_id)",
    "CREATE INDEX idx_vec_assets_item_id ON vec_assets(item_id)",
    "CREATE INDEX idx_rag_messages_conversation ON rag_messages(conversation_id, sort_index)"
  )
  if (include_target_type) {
    idx <- c(
      idx,
      "CREATE INDEX idx_llm_results_target_typed ON llm_results(target_type, target_id, job_type)"
    )
  }
  idx
}

page_asset_indexes <- c(
  "CREATE INDEX idx_assets_parent_asset_id ON assets(parent_asset_id)",
  "CREATE UNIQUE INDEX idx_assets_parent_page
     ON assets(parent_asset_id, page_number)
     WHERE parent_asset_id IS NOT NULL"
)

layouts_indexes <- c(
  "CREATE UNIQUE INDEX idx_layouts_asset_id_unique ON layouts(asset_id)",
  "CREATE INDEX idx_layouts_asset_id ON layouts(asset_id)"
)

rag_chunk_indexes <- c(
  "CREATE INDEX idx_rag_chunks_asset_id ON rag_chunks(asset_id)",
  "CREATE INDEX idx_rag_chunks_item_id ON rag_chunks(item_id)",
  "CREATE INDEX idx_rag_chunks_embedding_contract
     ON rag_chunks(embedding_model, embedding_contract, dimensions)"
)

rag_state_indexes <- "CREATE INDEX idx_rag_asset_embedding_state_due
  ON rag_asset_embedding_state(rag_incomplete, next_retry_at_ms)"

# ---------------------------------------------------------------------------
# Trigger builders
# ---------------------------------------------------------------------------
# rag_chunks_fts external-content triggers (migration 0029).
rag_fts_triggers <- c(
  "CREATE TRIGGER rag_chunks_fts_insert
   AFTER INSERT ON rag_chunks
   BEGIN
     INSERT INTO rag_chunks_fts(chunk_id, text_content)
     VALUES (NEW.id, NEW.text_content);
   END",
  "CREATE TRIGGER rag_chunks_fts_delete
   AFTER DELETE ON rag_chunks
   BEGIN
     DELETE FROM rag_chunks_fts WHERE chunk_id = OLD.id;
   END"
)

# 48 sync capture triggers (16 synced tables x 3 ops), src-tauri/src/sync/capture.rs.
sync_capture_triggers <- function() {
  tables <- c(
    "collections", "items", "assets", "notes", "annotations", "extractions",
    "transcriptions", "layouts", "entities", "triples", "topics", "item_topics",
    "llm_results", "rag_conversations", "rag_messages", "vec_assets"
  )
  out <- character(0)
  for (tbl in tables) {
    pk <- if (tbl == "vec_assets") "asset_id" else "id"
    specs <- list(
      list(suffix = "i", event = "INSERT", op = "I", ref = "NEW"),
      list(suffix = "u", event = "UPDATE", op = "U", ref = "NEW"),
      list(suffix = "d", event = "DELETE", op = "D", ref = "OLD")
    )
    for (s in specs) {
      out <- c(out, sprintf(
        "CREATE TRIGGER IF NOT EXISTS trg_sync_%s_%s AFTER %s ON %s
         WHEN COALESCE((SELECT value FROM sync_meta WHERE key='applying'),'0') <> '1'
          AND COALESCE((SELECT value FROM sync_meta WHERE key='capture_enabled'),'0') = '1'
         BEGIN
           INSERT INTO sync_oplog(table_name, row_id, op, changed_at)
           VALUES ('%s', %s.%s, '%s', CAST(unixepoch('subsec')*1000 AS INTEGER));
         END",
        tbl, s$suffix, s$event, tbl, tbl, s$ref, pk, s$op
      ))
    }
  }
  out
}

# 33 collection_activity_* triggers (migration 0027) maintaining
# collections.updated_at. Mirrors COLLECTION_ACTIVITY_DDL in runner.ts.
activity_touch <- function(where) {
  sprintf(
    "UPDATE collections
SET updated_at = MAX(
  updated_at + 1,
  CAST((julianday('now') - 2440587.5) * 86400000 AS INTEGER)
)
WHERE %s;",
    where
  )
}

activity_triggers_for <- function(tbl, scope) {
  ins <- sprintf(
    "CREATE TRIGGER collection_activity_%s_insert
AFTER INSERT ON %s
BEGIN
  %s
END",
    tbl, tbl, activity_touch(scope("NEW"))
  )
  upd <- sprintf(
    "CREATE TRIGGER collection_activity_%s_update
AFTER UPDATE ON %s
BEGIN
  %s
  %s
END",
    tbl, tbl, activity_touch(scope("OLD")), activity_touch(scope("NEW"))
  )
  del <- sprintf(
    "CREATE TRIGGER collection_activity_%s_delete
BEFORE DELETE ON %s
BEGIN
  %s
END",
    tbl, tbl, activity_touch(scope("OLD"))
  )
  c(ins, upd, del)
}

collection_activity_triggers <- function(include_llm = TRUE) {
  scope_items <- function(row) sprintf("id = %s.collection_id", row)
  scope_item_owned <- function(row) {
    sprintf("id IN (SELECT collection_id FROM items WHERE id = %s.item_id)", row)
  }
  scope_asset_owned <- function(row) {
    sprintf(
      "id IN (
  SELECT i.collection_id
  FROM items i
  JOIN assets a ON a.item_id = i.id
  WHERE a.id = %s.asset_id
)",
      row
    )
  }
  scope_llm <- function(row) {
    sprintf(
      "(%s.target_type IN ('collection', 'unknown') AND id = %s.target_id)
  OR (%s.target_type IN ('item', 'unknown') AND id IN (
    SELECT collection_id FROM items WHERE id = %s.target_id
  ))
  OR (%s.target_type IN ('asset', 'unknown') AND id IN (
    SELECT i.collection_id
    FROM items i
    JOIN assets a ON a.item_id = i.id
    WHERE a.id = %s.target_id
  ))",
      row, row, row, row, row, row
    )
  }

  out <- character(0)
  out <- c(out, activity_triggers_for("items", scope_items))
  for (tbl in c("assets", "notes", "entities", "triples", "vec_assets")) {
    out <- c(out, activity_triggers_for(tbl, scope_item_owned))
  }
  for (tbl in c("extractions", "layouts", "transcriptions", "annotations")) {
    out <- c(out, activity_triggers_for(tbl, scope_asset_owned))
  }
  # The llm_results activity trigger references target_type, which the
  # pre-0019 variant lacks, so it is gated.
  if (include_llm) {
    out <- c(out, activity_triggers_for("llm_results", scope_llm))
  }
  out
}

# ---------------------------------------------------------------------------
# Migration registry (names only; applied_at is deterministic seconds)
# ---------------------------------------------------------------------------
MIGRATION_NAMES <- c(
  "0001_initial", "0002_metadata_search", "0003_extractions", "0004_fts5",
  "0005_nlp_tables", "0006_triples", "0007_annotations", "0008_transcriptions",
  "0009_entities_provenance", "0010_entities_type_expansion",
  "0011_entities_geocoding", "0012_llm_results", "0013_assets_sort_index",
  "0014_asset_scoping", "0015_topics", "0016_asset_unique_ocr_transcription",
  "0017_vec_assets", "0018_fts_rowid_canonical", "0019_llm_results_target_type",
  "0020_layouts", "0021_drop_unused_processing_table", "0022_rag_conversations",
  "0023_sync_ids", "0024_pdf_page_assets", "0025_document_view_edits",
  "0026_entity_manual_coordinates", "0027_collection_activity",
  "0028_vec_assets_embedding_contract", "0029_rag_chunks"
)

insert_migrations <- function(con, names) {
  df <- data.frame(
    name = names,
    applied_at = secs(seq_along(names) * 60),
    stringsAsFactors = FALSE
  )
  dbWriteTable(con, "_migrations", df, append = TRUE, row.names = FALSE)
}

# ---------------------------------------------------------------------------
# Seed data
# ---------------------------------------------------------------------------
seed_core <- function(con, entity_unit = c("ms", "seconds")) {
  entity_unit <- match.arg(entity_unit)
  ts_entity <- if (entity_unit == "ms") ms else secs

  dbWriteTable(con, "collections", data.frame(
    id = COLL_1,
    name = "Archivo de prueba",
    description = "Colección de referencia para tests",
    created_at = ms(0), updated_at = ms(3600),
    stringsAsFactors = FALSE
  ), append = TRUE, row.names = FALSE)

  meta1 <- jsonlite::toJSON(list(
    `__entropia_file_metadata` = list(
      original_name = "manifiesto.pdf",
      original_path = "/docs/manifiesto.pdf",
      importedAt = "2026-01-15T12:05:00Z"
    ),
    page_count = 2L
  ), auto_unbox = TRUE)
  meta2 <- jsonlite::toJSON(list(
    `__entropia_file_metadata` = list(
      original_name = "carta.mp3",
      original_path = "/docs/carta.mp3",
      importedAt = "2026-01-15T12:06:00Z"
    )
  ), auto_unbox = TRUE)

  dbWriteTable(con, "items", data.frame(
    id = c(ITEM_1, ITEM_2, ITEM_3),
    title = c("Manifiesto de la huelga", "Carta al sindicato", "Fotografía de la marcha"),
    collection_id = COLL_1,
    metadata = c(as.character(meta1), as.character(meta2), NA_character_),
    created_at = c(ms(60), ms(180), ms(300)),
    updated_at = c(ms(120), ms(240), ms(360)),
    stringsAsFactors = FALSE
  ), append = TRUE, row.names = FALSE)
}

# ---------------------------------------------------------------------------
# Fixture builders
# ---------------------------------------------------------------------------
new_db <- function(name) {
  path <- file.path(out_dir, name)
  if (file.exists(path)) file.remove(path)
  dbConnect(SQLite(), path)
}

finish_db <- function(con) {
  dbExecute(con, "VACUUM")
  dbDisconnect(con)
}

build_mini <- function() {
  con <- new_db("mini.sqlite")
  on.exit(dbDisconnect(con), add = TRUE)
  for (ddl in c(T_MIGRATIONS, T_COLLECTIONS, T_ITEMS, T_ASSETS_PRE0019, T_NOTES)) {
    dbExecute(con, ddl)
  }
  for (idx in c(
    "CREATE INDEX idx_items_collection ON items(collection_id)",
    "CREATE INDEX idx_assets_item ON assets(item_id)",
    "CREATE INDEX idx_notes_item ON notes(item_id)"
  )) {
    dbExecute(con, idx)
  }
  insert_migrations(con, "0001_initial")
  seed_core(con)
  dbWriteTable(con, "notes", data.frame(
    id = NOTE_1, item_id = ITEM_1,
    content = "Nota al margen del manifiesto",
    created_at = ms(500), updated_at = ms(500),
    asset_id = NA_character_,
    stringsAsFactors = FALSE
  ), append = TRUE, row.names = FALSE)
  finish_db(con)
  invisible(NULL)
}

build_full_variant <- function(name,
                               migration_names,
                               entity_unit = "ms",
                               llm_target_type = TRUE,
                               include_post0018 = TRUE,
                               include_sync = TRUE,
                               include_activity = TRUE) {
  con <- new_db(name)
  # NOTE: no on.exit(disconnect) here -- the connection is returned to the
  # caller, which owns its lifecycle (and closes it via finish_db()).

  # Core tables.
  dbExecute(con, T_MIGRATIONS)
  dbExecute(con, T_COLLECTIONS)
  dbExecute(con, T_ITEMS)
  dbExecute(con, if (include_post0018) T_ASSETS else T_ASSETS_PRE0019)
  dbExecute(con, T_NOTES)
  dbExecute(con, T_EXTRACTIONS)
  dbExecute(con, if (llm_target_type) T_ENTITIES else T_ENTITIES_PRE0019)
  dbExecute(con, T_TRIPLES)
  dbExecute(con, if (include_post0018) T_ANNOTATIONS else T_ANNOTATIONS_PRE0019)
  dbExecute(con, T_TRANSCRIPTIONS)
  dbExecute(con, T_TOPICS)
  dbExecute(con, T_ITEM_TOPICS)
  dbExecute(con, if (llm_target_type) T_LLM_RESULTS else T_LLM_RESULTS_PRE0019)
  dbExecute(con, if (include_post0018) T_VEC_ASSETS else T_VEC_ASSETS_PRE0019)
  dbExecute(con, V_FTS_ITEMS)

  if (include_post0018) {
    dbExecute(con, T_LAYOUTS)
    dbExecute(con, T_RAG_CONVERSATIONS)
    dbExecute(con, T_RAG_MESSAGES)
    dbExecute(con, T_RAG_CHUNKS)
    dbExecute(con, V_RAG_CHUNKS_FTS)
    dbExecute(con, T_APP_SETTINGS)
    dbExecute(con, T_RAG_EMBEDDING_STATE)
  }

  # Indexes.
  for (idx in core_indexes(include_target_type = llm_target_type)) {
    dbExecute(con, idx)
  }
  if (include_post0018) {
    for (idx in c(page_asset_indexes, layouts_indexes, rag_chunk_indexes, rag_state_indexes)) {
      dbExecute(con, idx)
    }
  }

  # Sync bookkeeping tables. The capture TRIGGERS are created after seeding
  # (see apply_runtime_triggers) so they never fire during fixture build.
  if (include_sync) {
    for (ddl in SYNC_TABLES) dbExecute(con, ddl)
  }

  # rag_chunks_fts triggers must exist BEFORE seeding so the rag_chunks insert
  # populates the FTS index. They only touch rag_chunks_fts (no wall clock).
  if (include_post0018) {
    for (trg in rag_fts_triggers) dbExecute(con, trg)
  }

  insert_migrations(con, migration_names)
  seed_core(con, entity_unit = entity_unit)
  con
}

# Creates the triggers that reference wall-clock time (collection activity) or
# capture writes (sync oplog). These are installed ONLY after all seed data has
# been written, so they never fire during fixture generation; this keeps every
# timestamp fully deterministic.
apply_runtime_triggers <- function(con, include_sync, include_activity, llm_target_type) {
  if (include_activity) {
    for (trg in collection_activity_triggers(include_llm = llm_target_type)) {
      dbExecute(con, trg)
    }
  }
  if (include_sync) {
    for (trg in sync_capture_triggers()) dbExecute(con, trg)
  }
  invisible(NULL)
}

seed_full_rest <- function(con, llm_target_type = TRUE) {
  # assets: pdf parent + 2 pages + image + audio
  dbWriteTable(con, "assets", data.frame(
    id = c(ASSET_PDF, ASSET_PAGE1, ASSET_PAGE2, ASSET_IMG, ASSET_AUDIO),
    item_id = c(ITEM_1, ITEM_1, ITEM_1, ITEM_3, ITEM_2),
    path = c("store/manifiesto.pdf", "store/manifiesto_p1.pdf",
             "store/manifiesto_p2.pdf", "store/marcha.jpg", "store/carta.mp3"),
    type = c("pdf", "pdf", "pdf", "image", "audio"),
    size = c(20480L, 10240L, 10240L, 5120L, 40960L),
    created_at = c(ms(420), ms(430), ms(440), ms(450), ms(460)),
    sort_index = c(0L, 1L, 2L, 0L, 0L),
    parent_asset_id = c(NA, ASSET_PDF, ASSET_PDF, NA, NA),
    page_number = c(NA_integer_, 1L, 2L, NA_integer_, NA_integer_),
    stringsAsFactors = FALSE
  ), append = TRUE, row.names = FALSE)

  # extractions for pdf parent and page1 (page2 + image left without -> coverage gaps)
  dbWriteTable(con, "extractions", data.frame(
    id = c(EXT_PDF, EXT_PAGE1),
    asset_id = c(ASSET_PDF, ASSET_PAGE1),
    text_content = c(
      "![](page=1,bbox=[10,10,500,700]) La huelga general de 1920 movilizo a los obreros.",
      "Segunda pagina del manifiesto con demandas salariales."
    ),
    method = c("ocr", "pdf_paddle"),
    confidence = c(0.91, 0.88),
    created_at = c(ms(480), ms(490)),
    stringsAsFactors = FALSE
  ), append = TRUE, row.names = FALSE)

  # transcription for the audio asset
  segments <- jsonlite::toJSON(list(
    list(start_ms = 0L, end_ms = 2500L, text = "Compañeros"),
    list(start_ms = 2500L, end_ms = 5000L, text = "a la huelga")
  ), auto_unbox = TRUE)
  dbWriteTable(con, "transcriptions", data.frame(
    id = TRX_AUDIO, asset_id = ASSET_AUDIO,
    text_content = "Compañeros, a la huelga",
    language = "es", duration_ms = 60000L, model = "whisper-1",
    segments = as.character(segments), confidence = 0.95,
    created_at = ms(500),
    stringsAsFactors = FALSE
  ), append = TRUE, row.names = FALSE)

  # layouts for the pdf parent
  regions <- jsonlite::toJSON(list(list(kind = "text", bbox = list(10L, 10L, 500L, 700L))),
                              auto_unbox = TRUE)
  blocks <- jsonlite::toJSON(list(list(id = "b1", text = "La huelga")), auto_unbox = TRUE)
  dbWriteTable(con, "layouts", data.frame(
    id = LAY_PDF, asset_id = ASSET_PDF,
    regions = as.character(regions), blocks = as.character(blocks),
    model = "layout-model-1", image_width = 1000L, image_height = 1400L,
    created_at = ms(510),
    stringsAsFactors = FALSE
  ), append = TRUE, row.names = FALSE)

  # notes (one item-level, one asset-scoped)
  dbWriteTable(con, "notes", data.frame(
    id = c(NOTE_1, NOTE_2),
    item_id = c(ITEM_1, ITEM_1),
    content = c("Nota al margen del manifiesto", "Nota sobre la pagina uno"),
    created_at = c(ms(520), ms(530)), updated_at = c(ms(520), ms(530)),
    asset_id = c(NA_character_, ASSET_PDF),
    stringsAsFactors = FALSE
  ), append = TRUE, row.names = FALSE)

  # annotations (one rectangle on the pdf)
  dbWriteTable(con, "annotations", data.frame(
    id = ANN_1, asset_id = ASSET_PDF, page = 1L, kind = "rectangle",
    color = "#ff0000", x = 10, y = 10, width = 200, height = 50,
    created_at = ms(540), updated_at = ms(540),
    stringsAsFactors = FALSE
  ), append = TRUE, row.names = FALSE)
}

seed_research <- function(con, entity_unit = "ms") {
  ts_entity <- if (entity_unit == "ms") ms else secs

  # entities incl. one soft-deleted row
  dbWriteTable(con, "entities", data.frame(
    id = c(ENT_1, ENT_2, ENT_3, ENT_DEL),
    item_id = c(ITEM_1, ITEM_1, ITEM_2, ITEM_1),
    entity_type = c("person", "place", "organization", "person"),
    value = c("Juan Pérez", "Plaza de Mayo", "Sindicato Ferroviario", "Persona Borrada"),
    start_offset = c(0L, 12L, 5L, 0L),
    end_offset = c(10L, 24L, 26L, 14L),
    confidence = c(0.97, 0.93, 0.9, 0.5),
    source = c("ner", "ner", "ner", "manual_deleted"),
    model_name = c("spacy-es", "spacy-es", "spacy-es", NA_character_),
    created_at = c(ts_entity(600), ts_entity(610), ts_entity(620), ts_entity(630)),
    latitude = c(NA_real_, -34.608, NA_real_, NA_real_),
    longitude = c(NA_real_, -58.371, NA_real_, NA_real_),
    geo_status = c("pending", "resolved", "pending", "pending"),
    asset_id = c(NA, NA, NA, NA),
    stringsAsFactors = FALSE
  ), append = TRUE, row.names = FALSE)

  dbWriteTable(con, "triples", data.frame(
    id = TRIPLE_1, item_id = ITEM_1,
    subject = "Juan Pérez", predicate = "participo_en", object = "la huelga",
    created_at = ts_entity(640), asset_id = NA_character_,
    stringsAsFactors = FALSE
  ), append = TRUE, row.names = FALSE)

  dbWriteTable(con, "topics", data.frame(
    id = c(TOPIC_1, TOPIC_2),
    name = c("HUELGA", "SINDICATO"),
    created_at = c(ms(650), ms(660)),
    stringsAsFactors = FALSE
  ), append = TRUE, row.names = FALSE)

  dbWriteTable(con, "item_topics", data.frame(
    id = c(IT_1, IT_2),
    item_id = c(ITEM_1, ITEM_2),
    topic_id = c(TOPIC_1, TOPIC_2),
    created_at = c(ms(670), ms(680)),
    stringsAsFactors = FALSE
  ), append = TRUE, row.names = FALSE)
}

seed_ai <- function(con, llm_target_type = TRUE) {
  result_json <- jsonlite::toJSON(list(
    summary = "Documento sobre la huelga general.",
    tags = list("historia", "movimiento-obrero")
  ), auto_unbox = TRUE)

  if (llm_target_type) {
    dbWriteTable(con, "llm_results", data.frame(
      id = LLR_1, target_id = ITEM_1, target_type = "item",
      job_type = "summary", result = as.character(result_json),
      created_at = ms(700),
      stringsAsFactors = FALSE
    ), append = TRUE, row.names = FALSE)
  } else {
    dbWriteTable(con, "llm_results", data.frame(
      id = LLR_1, target_id = ITEM_1,
      job_type = "summary", result = as.character(result_json),
      created_at = ms(700),
      stringsAsFactors = FALSE
    ), append = TRUE, row.names = FALSE)
  }

  # RAG conversation + messages (assistant carries sources citations)
  dbWriteTable(con, "rag_conversations", data.frame(
    id = CONV_1, title = "Consulta sobre la huelga",
    created_at = ms(720), updated_at = ms(760),
    stringsAsFactors = FALSE
  ), append = TRUE, row.names = FALSE)

  sources_json <- jsonlite::toJSON(list(
    list(chunk_id = CHUNK_1, text = "La huelga de 1920", score = 0.9)
  ), auto_unbox = TRUE)
  dbWriteTable(con, "rag_messages", data.frame(
    id = c(MSG_1, MSG_2),
    conversation_id = CONV_1,
    sort_index = c(0L, 1L),
    role = c("user", "assistant"),
    content = c("¿Que paso en la huelga?", "Hubo una huelga general en 1920."),
    sources = c(NA_character_, as.character(sources_json)),
    model = c(NA_character_, "entropia-rag"),
    created_at = c(ms(730), ms(740)),
    stringsAsFactors = FALSE
  ), append = TRUE, row.names = FALSE)

  # vec_assets embedding (BLOB). RSQLite writes a list-column of raw vectors as
  # BLOBs via dbWriteTable.
  vec_df <- data.frame(
    asset_id = ASSET_IMG, item_id = ITEM_3,
    embedding_model = "baai/bge-m3",
    embedding_contract = "bge-m3-6000-char-weighted-mean-l2-v1",
    dimensions = 4L,
    stringsAsFactors = FALSE
  )
  vec_df$embedding <- list(EMB_VEC)
  dbWriteTable(con, "vec_assets", vec_df, append = TRUE, row.names = FALSE)

  # rag_chunks (the rag_chunks_fts_insert trigger populates the FTS index).
  chunk_df <- data.frame(
    id = CHUNK_1, asset_id = ASSET_PDF, item_id = ITEM_1,
    source_kind = "extraction", source_id = EXT_PDF,
    chunk_ordinal = 0L,
    text_content = "La huelga general de 1920 movilizo a los obreros.",
    start_char = 0L, end_char = 48L,
    source_text_hash = "hash-fixture-1",
    chunking_contract = "rag-chunk-800-100-char-v1",
    embedding_model = "baai/bge-m3",
    embedding_contract = "bge-m3-6000-char-weighted-mean-l2-v1",
    dimensions = 4L,
    stringsAsFactors = FALSE
  )
  chunk_df$embedding <- list(EMB_VEC)
  dbWriteTable(con, "rag_chunks", chunk_df, append = TRUE, row.names = FALSE)
}

seed_sync_and_settings <- function(con) {
  dbWriteTable(con, "sync_meta", data.frame(
    key = c("device_id", "server_url", "account_email", "last_pull_seq",
            "last_sync_at", "server_epoch", "triggers_version", "capture_enabled"),
    value = c("device-fixture", "https://cloud.entropia.example",
              "fixture@entropia.example", "42", as.character(ms(800)),
              "c3f5e8a0-1111-4111-8111-111111111111", "2", "1"),
    stringsAsFactors = FALSE
  ), append = TRUE, row.names = FALSE)

  dbWriteTable(con, "sync_row_versions", data.frame(
    table_name = c("items", "collections"),
    row_id = c(ITEM_1, COLL_1),
    server_seq = c(10L, 5L),
    stringsAsFactors = FALSE
  ), append = TRUE, row.names = FALSE)

  dbWriteTable(con, "sync_conflicts", data.frame(
    id = "conf-1", table_name = "items", row_id = ITEM_1,
    reason = "lww_lost", loser_payload = "{}", winner_summary = "{}",
    created_at = ms(810), acknowledged = 0L,
    stringsAsFactors = FALSE
  ), append = TRUE, row.names = FALSE)

  dbWriteTable(con, "app_settings", data.frame(
    key = c("language", "llm_mode", "embedding_provider",
            "openai_api_key", "openrouter_api_key"),
    value = c("es", "cloud", "openrouter",
              "sk-secret-should-not-surface", "or-secret-should-not-surface"),
    stringsAsFactors = FALSE
  ), append = TRUE, row.names = FALSE)

  dbWriteTable(con, "rag_asset_embedding_state", data.frame(
    asset_id = ASSET_IMG, item_id = ITEM_3,
    rag_incomplete = 0L, failure_count = 0L, next_retry_at_ms = 0L,
    last_error = NA_character_, updated_at_ms = ms(820),
    stringsAsFactors = FALSE
  ), append = TRUE, row.names = FALSE)
}

populate_fts_items <- function(con) {
  dbExecute(con, "
    INSERT INTO fts_items(rowid, item_id, title, metadata, extracted_text)
    SELECT i.rowid, i.id, i.title, COALESCE(i.metadata, ''),
           COALESCE((
             SELECT GROUP_CONCAT(text_part, ' ')
             FROM (
               SELECT text_part
               FROM (
                 SELECT COALESCE(e.text_content, '') AS text_part,
                        0 AS source_order,
                        COALESCE(a.sort_index, 0) AS sort_index,
                        e.created_at AS created_at
                 FROM extractions e
                 JOIN assets a ON a.id = e.asset_id
                 WHERE a.item_id = i.id
                 UNION ALL
                 SELECT COALESCE(t.text_content, '') AS text_part,
                        1 AS source_order,
                        COALESCE(a.sort_index, 0) AS sort_index,
                        t.created_at AS created_at
                 FROM transcriptions t
                 JOIN assets a ON a.id = t.asset_id
                 WHERE a.item_id = i.id
               ) ordered_text
               ORDER BY source_order ASC, sort_index ASC, created_at ASC
             )
           ), '')
    FROM items i
  ")
}

build_full <- function() {
  con <- build_full_variant(
    "full.sqlite",
    migration_names = MIGRATION_NAMES,
    entity_unit = "ms",
    llm_target_type = TRUE,
    include_post0018 = TRUE,
    include_sync = TRUE,
    include_activity = TRUE
  )
  seed_full_rest(con, llm_target_type = TRUE)
  seed_research(con, entity_unit = "ms")
  seed_ai(con, llm_target_type = TRUE)
  seed_sync_and_settings(con)
  populate_fts_items(con)
  apply_runtime_triggers(con, TRUE, TRUE, llm_target_type = TRUE)
  finish_db(con)
  invisible(NULL)
}

build_legacy_pre0019 <- function() {
  # Pre-0019: llm_results lacks target_type and _migrations stops at 0018.
  # All other tables are kept (the package must tolerate tables that exist
  # without a corresponding _migrations row -- a documented real-world case).
  con <- build_full_variant(
    "legacy-pre0019.sqlite",
    migration_names = MIGRATION_NAMES[MIGRATION_NAMES < "0019_llm_results_target_type"],
    entity_unit = "ms",
    llm_target_type = FALSE,
    include_post0018 = TRUE,
    include_sync = TRUE,
    include_activity = TRUE
  )
  seed_full_rest(con, llm_target_type = FALSE)
  seed_research(con, entity_unit = "ms")
  seed_ai(con, llm_target_type = FALSE)
  seed_sync_and_settings(con)
  populate_fts_items(con)
  apply_runtime_triggers(con, TRUE, TRUE, llm_target_type = FALSE)
  finish_db(con)
  invisible(NULL)
}

build_legacy_seconds <- function() {
  # Same complete schema as full, but entities/triples created_at are SECONDS.
  con <- build_full_variant(
    "legacy-seconds.sqlite",
    migration_names = MIGRATION_NAMES,
    entity_unit = "seconds",
    llm_target_type = TRUE,
    include_post0018 = TRUE,
    include_sync = TRUE,
    include_activity = TRUE
  )
  seed_full_rest(con, llm_target_type = TRUE)
  seed_research(con, entity_unit = "seconds")
  seed_ai(con, llm_target_type = TRUE)
  seed_sync_and_settings(con)
  populate_fts_items(con)
  apply_runtime_triggers(con, TRUE, TRUE, llm_target_type = TRUE)
  finish_db(con)
  invisible(NULL)
}

build_unknown_version <- function() {
  # Full schema, but _migrations head is a future migration newer than manifest.
  future <- c(MIGRATION_NAMES, "0030_future_schema")
  con <- build_full_variant(
    "unknown-version.sqlite",
    migration_names = future,
    entity_unit = "ms",
    llm_target_type = TRUE,
    include_post0018 = TRUE,
    include_sync = TRUE,
    include_activity = TRUE
  )
  seed_full_rest(con, llm_target_type = TRUE)
  seed_research(con, entity_unit = "ms")
  seed_ai(con, llm_target_type = TRUE)
  seed_sync_and_settings(con)
  populate_fts_items(con)
  apply_runtime_triggers(con, TRUE, TRUE, llm_target_type = TRUE)
  finish_db(con)
  invisible(NULL)
}

build_corrupt <- function() {
  # SQLite magic header followed by garbage: looks like SQLite, fails to open.
  path <- file.path(out_dir, "corrupt.sqlite")
  magic <- c(charToRaw("SQLite format 3"), as.raw(0L))
  junk <- as.raw(rep(c(0xde, 0xad, 0xbe, 0xef), 124))
  writeBin(c(magic, junk), path)
  invisible(NULL)
}

build_notsqlite <- function() {
  path <- file.path(out_dir, "notsqlite.txt")
  writeLines("This is not a SQLite database. Just plain text.", path)
  invisible(NULL)
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main <- function() {
  message("Generating entropiaR fixtures into: ", out_dir)
  build_mini()
  message("  - mini.sqlite")
  build_full()
  message("  - full.sqlite")
  build_legacy_pre0019()
  message("  - legacy-pre0019.sqlite")
  build_legacy_seconds()
  message("  - legacy-seconds.sqlite")
  build_unknown_version()
  message("  - unknown-version.sqlite")
  build_corrupt()
  message("  - corrupt.sqlite")
  build_notsqlite()
  message("  - notsqlite.txt")
  message("Done.")
}

main()
