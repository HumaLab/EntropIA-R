# make_example_db.R -- generate the package's example database
#
# Emits inst/extdata/entropia-example.sqlite: the database used by the runnable
# examples in the roxygen docs and the vignettes. It is the same deterministic
# full-schema fixture the test suite uses (every readable table, 3-5 rows each)
# with one difference: the fake `*_api_key` rows are stripped from app_settings
# so no key-shaped value ships with the package.
#
# Regenerate with (from the package root):
#   Rscript data-raw/make_example_db.R
#
# The output is deterministic: regenerating produces a byte-identical file, so
# the committed artifact and the build-time copy never diverge.

# Reuse the fixture builders (DDL + deterministic seed) from make_fixtures.R.
# Sourcing also regenerates the test fixtures, which is harmless and desired:
# they are gitignored and byte-identical on every run.
source(file.path("data-raw", "make_fixtures.R"))

# The package root was resolved inside make_fixtures.R (pkg_root global).
dest_dir <- file.path(pkg_root, "inst", "extdata")
dir.create(dest_dir, recursive = TRUE, showWarnings = FALSE)
dest <- file.path(dest_dir, "entropia-example.sqlite")

# Start from a fresh full-schema build in a temp location, then copy to dest so
# the dest file is written in one atomic step (never a half-written artifact).
tmp <- tempfile(fileext = ".sqlite")
con <- DBI::dbConnect(RSQLite::SQLite(), tmp)

# Same DDL + seed as the `full` test fixture.
for (ddl in c(
  T_MIGRATIONS, T_COLLECTIONS, T_ITEMS, T_ASSETS, T_NOTES, T_EXTRACTIONS,
  T_ENTITIES, T_TRIPLES, T_ANNOTATIONS, T_TRANSCRIPTIONS, T_TOPICS,
  T_ITEM_TOPICS, T_LLM_RESULTS, T_VEC_ASSETS, V_FTS_ITEMS, T_LAYOUTS,
  T_RAG_CONVERSATIONS, T_RAG_MESSAGES, T_RAG_CHUNKS, V_RAG_CHUNKS_FTS,
  T_APP_SETTINGS, T_RAG_EMBEDDING_STATE
)) {
  invisible(DBI::dbExecute(con, ddl))
}
for (idx in c(
  core_indexes(include_target_type = TRUE),
  page_asset_indexes, layouts_indexes, rag_chunk_indexes, rag_state_indexes
)) {
  invisible(DBI::dbExecute(con, idx))
}
for (ddl in SYNC_TABLES) invisible(DBI::dbExecute(con, ddl))
for (trg in rag_fts_triggers) invisible(DBI::dbExecute(con, trg))

invisible(insert_migrations(con, MIGRATION_NAMES))
invisible(seed_core(con, entity_unit = "ms"))
invisible(seed_full_rest(con, llm_target_type = TRUE))
invisible(seed_research(con, entity_unit = "ms"))
invisible(seed_ai(con, llm_target_type = TRUE))
invisible(seed_sync_and_settings(con))
invisible(populate_fts_items(con))
invisible(apply_runtime_triggers(con,
  include_sync = TRUE, include_activity = TRUE,
  llm_target_type = TRUE
))

# The example DB ships without key-shaped values.
invisible(DBI::dbExecute(con, "DELETE FROM app_settings WHERE key LIKE '%_api_key'"))
invisible(DBI::dbExecute(con, "VACUUM"))
DBI::dbDisconnect(con)

file.copy(tmp, dest, overwrite = TRUE)
message("Wrote example database: ", dest)
message("  ", file.info(dest)$size, " bytes")
