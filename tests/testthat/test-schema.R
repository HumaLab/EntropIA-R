# Tests for Task 5: schema introspection + column contract.
#
# Covers version detection, ent_tables/ent_columns (PRAGMA), the bundled
# manifest (ent_manifest), entropia_schema_info's merged surface, and the
# gap detection used by the Task 6 compatibility layer. All fixtures come
# from ent_fixture() (temp copies); never data-test/.

# Version expected per connectable fixture (mirrors test-fixtures.R).
schema_fixture_versions <- function() {
  list(
    mini = "0001_initial",
    full = "0029_rag_chunks",
    "legacy-pre0019" = "0018_fts_rowid_canonical",
    "legacy-seconds" = "0029_rag_chunks",
    "unknown-version" = "0030_future_schema"
  )
}

# Open a fixture, run f(con), always disconnect.
with_schema_con <- function(name, f) {
  con <- ent_connect_fixture(name)
  on.exit(try(entropia_disconnect(con), silent = TRUE), add = TRUE)
  f(con)
}

test_that("entropia_schema_version detects the head migration per fixture", {
  for (nm in names(schema_fixture_versions())) {
    v <- with_schema_con(nm, entropia_schema_version)
    expect_identical(v, schema_fixture_versions()[[nm]], info = nm)
  }
})

test_that("entropia_schema_version is NA without _migrations", {
  con <- entropia_connect(":memory:")
  expect_identical(entropia_schema_version(con), NA_character_)
  entropia_disconnect(con)
})

test_that("entropia_schema_version rejects a closed connection", {
  # allow policy: this test checks the closed-connection error, not schema compat.
  con <- withr::with_options(
    list(entropiaR.schema_policy = "allow"),
    entropia_connect(ent_fixture("mini"))
  )
  entropia_disconnect(con)
  expect_error(
    entropia_schema_version(con),
    class = "entropia_error_invalid_connection"
  )
})

test_that("ent_tables excludes SQLite internals and FTS shadow tables", {
  with_schema_con("full", function(con) {
    tabs <- ent_tables(con)
    expect_false("sqlite_sequence" %in% tabs)
    expect_false(any(startsWith(tabs, "sqlite_")))
    # FTS virtual tables are readable; their shadow tables are not.
    expect_true("fts_items" %in% tabs)
    expect_true("rag_chunks_fts" %in% tabs)
    expect_false("fts_items_data" %in% tabs)
    expect_false("fts_items_idx" %in% tabs)
    expect_false("rag_chunks_fts_content" %in% tabs)
    # Every core + sync table is visible.
    for (t in c(
      "collections", "items", "assets", "entities", "rag_chunks",
      "sync_meta", "sync_conflicts", "app_settings"
    )) {
      expect_true(t %in% tabs, info = t)
    }
  })
})

test_that("ent_columns reports columns via PRAGMA table_xinfo", {
  with_schema_con("full", function(con) {
    cols <- ent_columns(con, "collections")
    expect_s3_class(cols, "data.frame")
    expect_true(all(c("name", "type", "notnull", "pk", "hidden") %in% names(cols)))
    expect_identical(cols$name, c("id", "name", "description", "created_at", "updated_at"))
    expect_identical(cols$type, c("TEXT", "TEXT", "TEXT", "INTEGER", "INTEGER"))
    # PRAGMA reports the TEXT PRIMARY KEY as notnull = 0 unless declared NOT NULL.
    expect_identical(cols$notnull, c(FALSE, TRUE, FALSE, TRUE, TRUE))
    expect_true(cols$pk[1] == 1)
  })
})

test_that("ent_columns includes generated columns (search_text)", {
  with_schema_con("full", function(con) {
    cols <- ent_columns(con, "items")
    expect_true("search_text" %in% cols$name)
    row <- cols[cols$name == "search_text", , drop = FALSE]
    expect_false(row$notnull)
    expect_true(row$hidden >= 3)
  })
})

test_that("ent_columns errors with a stable class for a missing table", {
  with_schema_con("full", function(con) {
    expect_error(
      ent_columns(con, "does_not_exist"),
      class = "entropia_error_table_missing"
    )
  })
})

test_that("the manifest loads and covers every table the accessors need", {
  mf <- ent_manifest()
  expect_identical(mf$manifest_version, 1L)
  expect_identical(mf$schema_head, "0029_rag_chunks")
  expect_true(length(mf$tables) >= 20)
  for (t in c(
    "collections", "items", "assets", "extractions", "transcriptions",
    "layouts", "notes", "annotations", "entities", "triples", "topics",
    "item_topics", "llm_results", "rag_conversations", "rag_messages",
    "vec_assets", "rag_chunks", "fts_items", "rag_chunks_fts",
    "sync_meta", "sync_conflicts"
  )) {
    expect_true(t %in% names(mf$tables), info = t)
  }
})

test_that("the manifest carries the typed contract for every listed column", {
  mf <- ent_manifest()
  expect_identical(
    mf$tables$collections$columns$created_at$contract,
    "datetime_ms"
  )
  expect_identical(mf$tables$entities$columns$created_at$contract, "datetime_auto")
  expect_identical(mf$tables$triples$columns$created_at$contract, "datetime_auto")
  expect_identical(mf$tables$transcriptions$columns$segments$contract, "json")
  expect_identical(mf$tables$llm_results$columns$result$contract, "json")
  expect_identical(mf$tables$vec_assets$columns$embedding$contract, "blob_f32")
  expect_identical(mf$tables$rag_chunks$columns$embedding$contract, "blob_f32")
  # min_version tagging: target_type arrives with 0019.
  expect_identical(
    mf$tables$llm_results$columns$target_type$min_version,
    "0019_llm_results_target_type"
  )
  # repair/sync tables carry no migration.
  expect_false("min_version" %in% names(mf$tables$app_settings))
  expect_false("min_version" %in% names(mf$tables$sync_meta))
  # app_settings is whitelist-handled, not surfaced raw (Task 8).
  expect_true(all(c("device_id", "account_email", "last_sync_at") %in%
    mf$sync_meta_keys))
})

test_that("entropia_schema_info lists every readable table with correct types", {
  with_schema_con("full", function(con) {
    info <- entropia_schema_info(con)
    expect_s3_class(info, "tbl_df")
    expect_true(all(c(
      "table", "column", "type", "required", "contract",
      "min_version", "source"
    ) %in% names(info)))
    # Every manifest table is represented.
    mf <- ent_manifest()
    listed <- unique(info$table)
    for (t in names(mf$tables)) {
      expect_true(t %in% listed, info = t)
    }
    # Live-only tables (sync internals not in the manifest) show source schema.
    expect_true("sync_oplog" %in% listed)
    expect_identical(
      unique(info$source[info$table == "sync_oplog"]),
      "schema"
    )
    # Manifest columns report the contract surface.
    ent_created <- info[info$table == "entities" & info$column == "created_at", ]
    expect_identical(ent_created$contract, "datetime_auto")
    expect_identical(ent_created$source, "manifest")
    assets_type <- info[info$table == "assets" & info$column == "type", ]
    expect_identical(assets_type$type, "TEXT")
    expect_identical(assets_type$contract, "enum")
    # generated search_text is part of the contract surface
    st <- info[info$table == "items" & info$column == "search_text", ]
    expect_equal(nrow(st), 1L)
    expect_false(st$required)
  })
})

test_that("entropia_schema_info reports manifest-only columns as missing on legacy DBs", {
  with_schema_con("legacy-pre0019", function(con) {
    info <- entropia_schema_info(con)
    tt <- info[info$table == "llm_results" & info$column == "target_type", ]
    expect_equal(nrow(tt), 1L)
    expect_identical(tt$source, "manifest")
    expect_identical(tt$type, "TEXT")
    expect_true(tt$required)
    expect_identical(tt$min_version, "0019_llm_results_target_type")
  })
})

test_that("ent_schema_gaps is empty on a healthy post-0029 schema", {
  with_schema_con("full", function(con) {
    g <- ent_schema_gaps(con)
    expect_equal(nrow(g), 0L)
  })
  with_schema_con("legacy-seconds", function(con) {
    expect_equal(nrow(ent_schema_gaps(con)), 0L)
  })
})

test_that("ent_schema_gaps detects legacy columns as expected-but-not-yet", {
  with_schema_con("legacy-pre0019", function(con) {
    g <- ent_schema_gaps(con)
    tt <- g[g$table == "llm_results" & g$column == "target_type", ]
    expect_equal(nrow(tt), 1L)
    expect_true(tt$required)
    expect_false(tt$expected) # version 0018 < 0019 -> not yet expected
    expect_identical(tt$current_version, "0018_fts_rowid_canonical")
  })
  with_schema_con("mini", function(con) {
    g <- ent_schema_gaps(con)
    expect_true(all(g$expected == FALSE))
    expect_true("page_number" %in% g$column[g$table == "assets"])
  })
})

test_that("ent_schema_gaps flags a genuinely missing required column", {
  # A scratch DB at 0001_initial whose items table lacks the required title.
  tmp <- tempfile(fileext = ".sqlite")
  db <- DBI::dbConnect(RSQLite::SQLite(), tmp)
  DBI::dbExecute(
    db,
    "CREATE TABLE _migrations (
       id INTEGER PRIMARY KEY AUTOINCREMENT,
       name TEXT NOT NULL UNIQUE,
       applied_at INTEGER NOT NULL)"
  )
  DBI::dbExecute(
    db,
    "INSERT INTO _migrations (name, applied_at) VALUES ('0001_initial', 1768478400)"
  )
  DBI::dbExecute(
    db,
    "CREATE TABLE items (id TEXT PRIMARY KEY, collection_id TEXT NOT NULL)"
  )
  DBI::dbDisconnect(db)

  # The connect-time policy (Task 6) aborts on missing required columns, so
  # this test opens under the allow policy: it exercises ent_schema_gaps, not
  # the connect guard.
  withr::with_options(list(entropiaR.schema_policy = "allow"), {
    con <- entropia_connect(tmp)
    on.exit(entropia_disconnect(con), add = TRUE)
    g <- ent_schema_gaps(con)
    title <- g[g$table == "items" & g$column == "title", ]
    expect_equal(nrow(title), 1L)
    expect_true(title$required)
    expect_true(title$expected) # version 0001_initial >= min_version 0001_initial
    # The gap is absent from the live schema_info column set but present in the
    # manifest surface with source = manifest.
    info <- entropia_schema_info(con)
    expect_true("title" %in% info$column[info$table == "items"])
  })
})
