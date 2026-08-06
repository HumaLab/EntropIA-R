# Tests for Task 7: diagnostics (entropia_validate + entropia_status).
#
# validate() reports structural findings (it never raises for missing
# tables/columns); status() renders a read-only summary. All fixtures come
# from ent_fixture() temp copies; the reference corpus is never opened.

# Scratch DBs hand-rolled in tempdir so tests can exercise structural
# deviations the checked-in fixtures do not ship.

# A DB at 0029_rag_chunks with the core backbone present but zero rows.
scratch_db_empty_core <- function() {
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
    "INSERT INTO _migrations (name, applied_at) VALUES ('0029_rag_chunks', 1768478400)"
  )
  DBI::dbExecute(
    db,
    "CREATE TABLE collections (
       id TEXT PRIMARY KEY, name TEXT NOT NULL,
       created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)"
  )
  DBI::dbExecute(
    db,
    "CREATE TABLE items (
       id TEXT PRIMARY KEY, title TEXT NOT NULL, collection_id TEXT NOT NULL,
       created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)"
  )
  DBI::dbExecute(
    db,
    "CREATE TABLE assets (
       id TEXT PRIMARY KEY, item_id TEXT NOT NULL, path TEXT NOT NULL,
       type TEXT NOT NULL, created_at INTEGER NOT NULL, sort_index INTEGER NOT NULL)"
  )
  DBI::dbDisconnect(db)
  tmp
}

# A DB at 0029_rag_chunks missing the items table (broken core backbone).
scratch_db_missing_core_table <- function() {
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
    "INSERT INTO _migrations (name, applied_at) VALUES ('0029_rag_chunks', 1768478400)"
  )
  DBI::dbExecute(
    db,
    "CREATE TABLE collections (
       id TEXT PRIMARY KEY, name TEXT NOT NULL,
       created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)"
  )
  DBI::dbExecute(
    db,
    "CREATE TABLE assets (
       id TEXT PRIMARY KEY, item_id TEXT NOT NULL, path TEXT NOT NULL,
       type TEXT NOT NULL, created_at INTEGER NOT NULL, sort_index INTEGER NOT NULL)"
  )
  DBI::dbDisconnect(db)
  tmp
}

# A DB at 0001_initial whose items table lacks the required title column.
scratch_db_missing_req_col <- function() {
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
    "CREATE TABLE collections (
       id TEXT PRIMARY KEY, name TEXT NOT NULL,
       created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)"
  )
  DBI::dbExecute(
    db,
    "CREATE TABLE assets (
       id TEXT PRIMARY KEY, item_id TEXT NOT NULL, path TEXT NOT NULL,
       type TEXT NOT NULL, created_at INTEGER NOT NULL)"
  )
  DBI::dbExecute(
    db,
    "CREATE TABLE items (
       id TEXT PRIMARY KEY, collection_id TEXT NOT NULL,
       created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)"
  )
  DBI::dbDisconnect(db)
  tmp
}

# Open a fixture, run f(con), always disconnect.
with_validate_con <- function(name, f) {
  con <- ent_connect_fixture(name)
  on.exit(try(entropia_disconnect(con), silent = TRUE), add = TRUE)
  f(con)
}

# --- entropia_validate: findings ---------------------------------------------

test_that("entropia_validate finds nothing on healthy fixtures", {
  for (nm in c("full", "legacy-seconds", "legacy-pre0019", "unknown-version")) {
    with_validate_con(nm, function(con) {
      v <- entropia_validate(con)
      expect_equal(nrow(v), 0L, info = nm)
      expect_identical(attr(v, "schema_version"),
                       entropia_schema_version(con), info = nm)
    })
  }
})

test_that("entropia_validate returns a well-formed findings tibble", {
  with_validate_con("full", function(con) {
    v <- entropia_validate(con)
    expect_s3_class(v, "tbl_df")
    expect_true(all(c("severity", "kind", "table", "column", "message") %in%
                      names(v)))
    rc <- attr(v, "row_counts")
    expect_type(rc, "integer")
    expect_true("items" %in% names(rc))
    expect_identical(unname(rc[["items"]]), 3L)
  })
})

test_that("entropia_validate tolerates a minimal (mini) schema with warnings", {
  with_validate_con("mini", function(con) {
    v <- entropia_validate(con)
    expect_false(any(v$severity == "error"))
    # sync/repair tables carry no migration so they are expected at any
    # version; their absence on a minimal core schema is a warning, not an error.
    expect_true("sync_meta" %in% v$table[v$kind == "table_missing"])
    expect_identical(unname(attr(v, "row_counts")[["items"]]), 3L)
  })
})

test_that("entropia_validate reports a missing core table as an error finding", {
  tmp <- scratch_db_missing_core_table()
  withr::with_options(list(entropiaR.schema_policy = "allow"), {
    con <- entropia_connect(tmp)
    on.exit(entropia_disconnect(con), add = TRUE)
    v <- entropia_validate(con)
    hit <- v[v$kind == "table_missing" & v$table == "items", ]
    expect_equal(nrow(hit), 1L)
    expect_identical(hit$severity, "error")
  })
})

test_that("entropia_validate reports a missing required column as an error finding", {
  tmp <- scratch_db_missing_req_col()
  withr::with_options(list(entropiaR.schema_policy = "allow"), {
    con <- entropia_connect(tmp)
    on.exit(entropia_disconnect(con), add = TRUE)
    v <- entropia_validate(con)
    hit <- v[v$kind == "column_missing" & v$table == "items" &
               v$column == "title", ]
    expect_equal(nrow(hit), 1L)
    expect_identical(hit$severity, "error")
    # Older-but-not-yet columns (min_version not reached) are not flagged.
    expect_false(any(v$column %in% "target_type"))
  })
})

test_that("entropia_validate flags an empty database as a warning", {
  tmp <- scratch_db_empty_core()
  withr::with_options(list(entropiaR.schema_policy = "allow"), {
    con <- entropia_connect(tmp)
    on.exit(entropia_disconnect(con), add = TRUE)
    v <- entropia_validate(con)
    expect_true("empty_database" %in% v$kind)
    expect_false(any(v$severity == "error"))
  })
})

test_that("entropia_validate diagnoses a database with no tables", {
  # A valid SQLite file with no user tables: create then drop leaves the file
  # header in place with an empty sqlite_master.
  tmp <- tempfile(fileext = ".sqlite")
  db <- DBI::dbConnect(RSQLite::SQLite(), tmp)
  DBI::dbExecute(db, "CREATE TABLE _scratch (a INTEGER)")
  DBI::dbExecute(db, "DROP TABLE _scratch")
  DBI::dbDisconnect(db)
  con <- entropia_connect(tmp) # no _migrations -> compat policy is skipped
  on.exit(entropia_disconnect(con), add = TRUE)
  v <- entropia_validate(con)
  expect_true(all(c("collections", "items", "assets") %in%
                    v$table[v$kind == "table_missing"]))
  expect_true("no_migrations" %in% v$kind)
})

test_that("entropia_validate reports an unreadable database", {
  con <- suppressWarnings(DBI::dbConnect(
    RSQLite::SQLite(), ent_fixture("corrupt"), flags = RSQLite::SQLITE_RO
  ))
  on.exit(try(DBI::dbDisconnect(con), silent = TRUE), add = TRUE)
  v <- entropia_validate(con)
  expect_equal(nrow(v), 1L)
  expect_identical(v$kind, "unreadable")
  expect_identical(v$severity, "error")
})

test_that("error classes stay stable while validate reports findings", {
  with_validate_con("full", function(con) {
    # The accessor primitives raise the stable classes.
    expect_error(ent_columns(con, "does_not_exist"),
                 class = "entropia_error_table_missing")
    expect_error(ent_require_columns(con, "items", c("id", "title", "nope")),
                 class = "entropia_error_column_missing")
  })
  # validate reports the same situation as findings, never as errors.
  tmp <- scratch_db_missing_req_col()
  withr::with_options(list(entropiaR.schema_policy = "allow"), {
    con <- entropia_connect(tmp)
    on.exit(entropia_disconnect(con), add = TRUE)
    expect_no_error(v <- entropia_validate(con))
    expect_true(any(v$kind == "column_missing"))
  })
})

test_that("entropia_validate and entropia_status reject a closed connection", {
  con <- withr::with_options(
    list(entropiaR.schema_policy = "allow"),
    entropia_connect(ent_fixture("mini"))
  )
  entropia_disconnect(con)
  expect_error(entropia_validate(con),
               class = "entropia_error_invalid_connection")
  expect_error(entropia_status(con),
               class = "entropia_error_invalid_connection")
})

# --- entropia_status ---------------------------------------------------------

test_that("entropia_status reports path, mode, schema and row counts", {
  with_validate_con("full", function(con) {
    st <- entropia_status(con)
    expect_s3_class(st, "entropia_status")
    expect_identical(st$mode, "read-only")
    expect_identical(st$schema_version, "0029_rag_chunks")
    expect_true(st$valid)
    expect_true(is.character(st$path) && nzchar(st$path))
    expect_true("items" %in% names(st$row_counts))
    expect_true(all(is.integer(st$row_counts)))
    expect_identical(st$wal$journal_mode, "delete")
    expect_false(st$wal$wal_present)
  })
})

test_that("entropia_status reads sync freshness from sync_meta", {
  with_validate_con("full", function(con) {
    st <- entropia_status(con)
    expect_s3_class(st$sync$last_sync_at, "POSIXct")
    expect_identical(st$sync$last_sync_at,
                     as.POSIXct(1768479200, origin = "1970-01-01", tz = "UTC"))
    expect_true(st$sync$capture_enabled)
    expect_identical(st$sync$triggers_version, 2L)
  })
})

test_that("entropia_status reports never-synced without sync_meta", {
  with_validate_con("mini", function(con) {
    st <- entropia_status(con)
    expect_true(is.na(st$sync$last_sync_at))
    expect_true(is.na(st$sync$capture_enabled))
    expect_true(is.na(st$sync$triggers_version))
  })
})

test_that("entropia_status works on a raw DBI connection", {
  con <- DBI::dbConnect(RSQLite::SQLite(), ent_fixture("full"),
                        flags = RSQLite::SQLITE_RO)
  on.exit(try(DBI::dbDisconnect(con), silent = TRUE), add = TRUE)
  st <- entropia_status(con)
  expect_false(is.na(st$path))
  expect_identical(st$schema_version, "0029_rag_chunks")
})

test_that("entropia_status detects WAL sidecars", {
  p <- tempfile(fileext = ".sqlite")
  db <- DBI::dbConnect(RSQLite::SQLite(), p)
  DBI::dbExecute(db, "PRAGMA journal_mode = WAL")
  DBI::dbExecute(db, "CREATE TABLE t (x INTEGER)")
  DBI::dbExecute(db, "INSERT INTO t VALUES (1)")
  on.exit(try(DBI::dbDisconnect(db), silent = TRUE), add = TRUE)
  con <- entropia_connect(p) # no _migrations -> compat policy is skipped
  on.exit(entropia_disconnect(con), add = TRUE)
  st <- entropia_status(con)
  expect_identical(st$wal$journal_mode, "wal")
  expect_true(st$wal$wal_present)
  expect_true(st$wal$shm_present)
  expect_true(is.numeric(st$wal$wal_size) && st$wal$wal_size > 0)
})

test_that("entropia_status prints a compact summary", {
  with_validate_con("full", function(con) {
    out <- capture.output(print(entropia_status(con)))
    expect_true(any(grepl("entropiaR status", out)))
    expect_true(any(grepl("schema version", out)))
    expect_true(any(grepl("last_sync_at", out)))
    expect_true(any(grepl("row counts", out)))
  })
})
