# make_manifest.R -- deterministic schema-manifest generator for entropiaR
#
# Rebuilds inst/schemas/manifest.json, the shipped column contract for the
# post-0029 EntropIA schema. Column names/types/notnull/pk are read from the
# full fixture (tests/testthat/fixtures/full.sqlite) so the contract always
# matches a schema the test suite actually exercises; the typing contract, the
# migration that guarantees each column, and enum values are declared below.
#
# Regenerate with (from the package root):
#   Rscript data-raw/make_manifest.R
#
# The manifest itself is checked in; this script only documents how it was
# derived and keeps the derivation reproducible.

suppressMessages({
  library(DBI)
  library(RSQLite)
  library(jsonlite)
})

# ---------------------------------------------------------------------------
# Locations
# ---------------------------------------------------------------------------
script_path <- (function() {
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (length(file_arg) > 0) {
    return(normalizePath(sub("^--file=", "", file_arg[1]), winslash = "/"))
  }
  normalizePath(file.path("data-raw", "make_manifest.R"), winslash = "/")
})()
pkg_root <- normalizePath(dirname(dirname(script_path)), winslash = "/")
full_path <- file.path(pkg_root, "tests", "testthat", "fixtures", "full.sqlite")
stopifnot(file.exists(full_path))
out_path <- file.path(pkg_root, "inst", "schemas", "manifest.json")
dir.create(dirname(out_path), recursive = TRUE, showWarnings = FALSE)

con <- DBI::dbConnect(RSQLite::SQLite(), full_path, flags = RSQLite::SQLITE_RO)
on.exit(DBI::dbDisconnect(con), add = TRUE)

# ---------------------------------------------------------------------------
# Contract declarations (source of truth below the live column read)
# ---------------------------------------------------------------------------

# The readable surface: every table the package understands, in the order it
# should appear in documentation. Excludes SQLite internals and FTS shadows.
manifest_tables <- c(
  "_migrations", "collections", "items", "assets", "extractions",
  "transcriptions", "layouts", "notes", "annotations", "entities", "triples",
  "topics", "item_topics", "llm_results", "rag_conversations", "rag_messages",
  "vec_assets", "rag_chunks", "fts_items", "rag_chunks_fts",
  "sync_meta", "sync_row_versions", "sync_conflicts", "sync_blob_index",
  "app_settings", "rag_asset_embedding_state"
)

# Where each table comes from: a _migrations entry, the Rust runtime repairs,
# or the sync engine. Repair/sync tables carry no migration and may appear at
# any schema version.
sources <- c(
  `_migrations` = "migration", collections = "migration", items = "migration",
  assets = "migration", extractions = "migration", transcriptions = "migration",
  layouts = "migration", notes = "migration", annotations = "migration",
  entities = "migration", triples = "migration", topics = "migration",
  item_topics = "migration", llm_results = "migration",
  rag_conversations = "migration", rag_messages = "migration",
  vec_assets = "migration", rag_chunks = "migration", fts_items = "migration",
  rag_chunks_fts = "migration",
  sync_meta = "sync", sync_row_versions = "sync", sync_conflicts = "sync",
  sync_blob_index = "sync",
  app_settings = "repair", rag_asset_embedding_state = "repair"
)

# Earliest migration that guarantees each table exists. NULL means no
# migration guarantees it (repair/sync tables).
min_versions <- c(
  `_migrations` = "0001_initial", collections = "0001_initial",
  items = "0001_initial", assets = "0001_initial",
  extractions = "0003_extractions", transcriptions = "0008_transcriptions",
  layouts = "0020_layouts", notes = "0001_initial",
  annotations = "0007_annotations", entities = "0005_nlp_tables",
  triples = "0006_triples", topics = "0015_topics", item_topics = "0015_topics",
  llm_results = "0012_llm_results", rag_conversations = "0022_rag_conversations",
  rag_messages = "0022_rag_conversations", vec_assets = "0017_vec_assets",
  rag_chunks = "0029_rag_chunks", fts_items = "0004_fts5",
  rag_chunks_fts = "0029_rag_chunks"
)

# Per-column overrides: the migration that guarantees a column added after the
# table was first created.
col_min_versions <- list(
  items = c(metadata = "0002_metadata_search", search_text = "0002_metadata_search"),
  assets = c(
    sort_index = "0013_assets_sort_index",
    parent_asset_id = "0024_pdf_page_assets",
    page_number = "0024_pdf_page_assets"
  ),
  notes = c(asset_id = "0014_asset_scoping"),
  entities = c(
    source = "0009_entities_provenance",
    model_name = "0009_entities_provenance",
    latitude = "0011_entities_geocoding",
    longitude = "0011_entities_geocoding",
    geo_status = "0011_entities_geocoding",
    asset_id = "0014_asset_scoping",
    manual_lat = "0026_entity_manual_coordinates",
    manual_lon = "0026_entity_manual_coordinates"
  ),
  triples = c(asset_id = "0014_asset_scoping"),
  llm_results = c(target_type = "0019_llm_results_target_type"),
  vec_assets = c(
    embedding_model = "0028_vec_assets_embedding_contract",
    embedding_contract = "0028_vec_assets_embedding_contract",
    dimensions = "0028_vec_assets_embedding_contract"
  )
)

# Typing contract per Technical Details in the plan. Column name -> contract.
# The recognized contracts are the datetime magnitudes, JSON, blob, numeric
# and enum families described in the plan's column type map.
contract_map <- list(
  `_migrations` = c(applied_at = "datetime_s"),
  collections = c(created_at = "datetime_ms", updated_at = "datetime_ms"),
  items = c(metadata = "json", created_at = "datetime_ms", updated_at = "datetime_ms"),
  assets = c(created_at = "datetime_ms", size = "int", type = "enum"),
  extractions = c(created_at = "datetime_ms", confidence = "dbl"),
  transcriptions = c(
    created_at = "datetime_ms", segments = "json", duration_ms = "int",
    confidence = "dbl"
  ),
  layouts = c(
    created_at = "datetime_ms", regions = "json", blocks = "json",
    image_width = "int", image_height = "int"
  ),
  notes = c(created_at = "datetime_ms", updated_at = "datetime_ms"),
  annotations = c(
    created_at = "datetime_ms", updated_at = "datetime_ms", x = "dbl",
    y = "dbl", width = "dbl", height = "dbl", page = "int", kind = "enum"
  ),
  entities = c(
    created_at = "datetime_auto", confidence = "dbl", start_offset = "int",
    end_offset = "int", entity_type = "enum", latitude = "dbl",
    longitude = "dbl", manual_lat = "dbl", manual_lon = "dbl",
    geo_status = "enum"
  ),
  triples = c(created_at = "datetime_auto"),
  topics = c(created_at = "datetime_ms"),
  item_topics = c(created_at = "datetime_ms"),
  llm_results = c(created_at = "datetime_ms", result = "json", target_type = "enum"),
  rag_conversations = c(created_at = "datetime_ms", updated_at = "datetime_ms"),
  rag_messages = c(created_at = "datetime_ms", sources = "json", role = "enum"),
  vec_assets = c(embedding = "blob_f32", dimensions = "int"),
  rag_chunks = c(
    embedding = "blob_f32", start_char = "int", end_char = "int",
    chunk_ordinal = "int", dimensions = "int", source_kind = "enum"
  ),
  sync_conflicts = c(created_at = "datetime_ms", reason = "enum"),
  rag_asset_embedding_state = c(
    next_retry_at_ms = "datetime_ms", updated_at_ms = "datetime_ms"
  )
)

# Known enum values, derived from the schema CHECK constraints and the domain
# model in the plan (assets.type has no CHECK in the fixture but the app
# documents image|pdf|audio).
enum_values <- list(
  assets = list(type = c("image", "pdf", "audio")),
  annotations = list(kind = c("rectangle", "underline", "crop", "erase", "rotation")),
  entities = list(
    entity_type = c("person", "place", "date", "institution", "organization", "misc", "custom")
  ),
  llm_results = list(target_type = c("asset", "item", "collection", "unknown")),
  rag_messages = list(role = c("user", "assistant")),
  rag_chunks = list(source_kind = c("extraction", "transcription"))
)

# FTS virtual tables declare no column types (PRAGMA returns ""); the readable
# columns are text.
type_overrides <- list(
  fts_items = c(
    item_id = "TEXT", title = "TEXT", metadata = "TEXT", extracted_text = "TEXT"
  ),
  rag_chunks_fts = c(chunk_id = "TEXT", text_content = "TEXT")
)

# ---------------------------------------------------------------------------
# Build the manifest
# ---------------------------------------------------------------------------
tables_json <- list()
for (t in manifest_tables) {
  cols <- DBI::dbGetQuery(con, sprintf("PRAGMA table_xinfo('%s')", t))
  cols <- cols[cols$hidden == 0 | cols$hidden >= 3, , drop = FALSE]
  mv_base <- if (t %in% names(min_versions)) unname(min_versions[[t]]) else NULL
  overrides <- if (t %in% names(col_min_versions)) col_min_versions[[t]] else list()
  contracts <- if (t %in% names(contract_map)) contract_map[[t]] else list()
  enums <- if (t %in% names(enum_values)) enum_values[[t]] else list()
  tos <- if (t %in% names(type_overrides)) type_overrides[[t]] else list()

  colmap <- list()
  for (i in seq_len(nrow(cols))) {
    nm <- cols$name[i]
    typ <- cols$type[i]
    if (!nzchar(typ) && nm %in% names(tos)) typ <- unname(tos[[nm]])
    mv <- if (nm %in% names(overrides)) unname(overrides[[nm]]) else mv_base
    entry <- list(
      type = typ,
      required = as.logical(cols$notnull[i] | cols$pk[i] > 0)
    )
    if (!is.null(mv)) entry$min_version <- mv
    if (nm %in% names(contracts)) entry$contract <- unname(contracts[[nm]])
    if (nm %in% names(enums)) entry$values <- unname(enums[[nm]])
    colmap[[nm]] <- entry
  }

  tbl_entry <- list(source = unname(sources[[t]]), columns = colmap)
  if (!is.null(mv_base)) tbl_entry$min_version <- mv_base
  tables_json[[t]] <- tbl_entry
}

manifest <- list(
  manifest_version = 1L,
  schema_head = "0029_rag_chunks",
  description = paste0(
    "entropiaR column contract for the post-0029 EntropIA schema. ",
    "required marks columns whose absence is a compatibility failure once the ",
    "database version reaches the column's min_version; contract records the ",
    "typed transformation entropia_collect applies."
  ),
  sync_meta_keys = c(
    "device_id", "account_email", "server_url", "last_sync_at",
    "server_epoch", "triggers_version", "capture_enabled"
  ),
  tables = tables_json
)

jsonlite::write_json(manifest, out_path, pretty = TRUE, auto_unbox = TRUE)

cat("Wrote", out_path, "\n")
cat("Tables:", length(manifest_tables), "\n")
