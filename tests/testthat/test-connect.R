# Tests for Task 4: entropia_connect read-only + S3/S4 class.
#
# Covers the connection contract: read-only enforcement, :memory: support,
# S3/S4 methods, idempotent disconnect, WAL-aware copy and the error paths.
# All fixtures come from ent_fixture() (temp copies); never data-test/.

# These tests exercise the connection contract, not the schema-policy layer
# (Task 6); connect to older fixtures under the allow policy so they don't
# warn.
connect_quiet <- function(path, ...) {
  withr::with_options(
    list(entropiaR.schema_policy = "allow"),
    entropia_connect(path, ...)
  )
}

test_that("entropia_connect returns a typed read-only connection", {
  con <- connect_quiet(ent_fixture("mini"))
  expect_s4_class(con, "entropia_conn")
  expect_true(methods::is(con, "SQLiteConnection"))
  expect_identical(attr(con, "mode"), "read-only")
  expect_identical(attr(con, "schema_version"), "0001_initial")
  expect_true(nzchar(attr(con, "schema_hash")))
  expect_true(DBI::dbIsValid(con))
  entropia_disconnect(con)
})

test_that("entropia_connect enforces read-only", {
  con <- connect_quiet(ent_fixture("mini"))
  expect_error(
    DBI::dbWriteTable(con, "x", data.frame(a = 1)),
    "readonly"
  )
  expect_error(
    DBI::dbExecute(con, "DROP TABLE collections"),
    "readonly"
  )
  entropia_disconnect(con)
})

test_that("entropia_connect rejects write = TRUE in v1", {
  expect_error(
    entropia_connect(ent_fixture("mini"), write = TRUE),
    class = "entropia_error_write_disabled"
  )
})

test_that("entropia_connect supports :memory:", {
  con <- connect_quiet(":memory:")
  expect_s4_class(con, "entropia_conn")
  expect_identical(attr(con, "path"), ":memory:")
  expect_true(DBI::dbIsValid(con))
  entropia_disconnect(con)
  expect_false(DBI::dbIsValid(con))
})

test_that("entropia_conn methods behave", {
  con <- connect_quiet(ent_fixture("mini"))
  expect_output(print(con), "entropiaR connection")
  expect_type(format(con), "character")
  expect_match(format(con), "read-only")

  s <- summary(con)
  expect_s3_class(s, "summary.entropia_conn")
  expect_identical(s$mode, "read-only")
  expect_identical(s$schema_version, "0001_initial")
  expect_true(s$valid)
  expect_output(print(s), "schema version")

  expect_error(dplyr::collect(con), class = "entropia_error_unsupported")
  entropia_disconnect(con)
})

test_that("entropia_disconnect is idempotent", {
  con <- connect_quiet(ent_fixture("mini"))
  expect_true(DBI::dbIsValid(con))
  entropia_disconnect(con)
  expect_false(DBI::dbIsValid(con))
  expect_silent(entropia_disconnect(con))
})

test_that("entropia_copy snapshots a plain file DB", {
  con <- connect_quiet(ent_fixture("mini"))
  dest <- tempfile(fileext = ".sqlite")
  entropia_copy(con, dest)
  expect_true(file.exists(dest))

  con2 <- connect_quiet(dest)
  expect_identical(
    DBI::dbListTables(con2),
    DBI::dbListTables(con)
  )
  expect_identical(
    DBI::dbGetQuery(con2, "SELECT COUNT(*) AS n FROM collections")$n,
    DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM collections")$n
  )
  entropia_disconnect(con2)
  entropia_disconnect(con)
})

test_that("entropia_copy is WAL-aware with live sidecars", {
  src <- tempfile(fileext = ".sqlite")
  db <- DBI::dbConnect(RSQLite::SQLite(), src)
  DBI::dbExecute(db, "CREATE TABLE t (a INTEGER)")
  DBI::dbExecute(db, "PRAGMA journal_mode = WAL")
  DBI::dbExecute(db, "INSERT INTO t VALUES (1)")
  DBI::dbExecute(db, "INSERT INTO t VALUES (2)")
  expect_true(file.exists(paste0(src, "-wal")))
  expect_true(file.exists(paste0(src, "-shm")))

  con <- connect_quiet(src)
  expect_identical(ent_snapshot_hash(con), NA_character_)
  dest <- tempfile(fileext = ".sqlite")
  entropia_copy(con, dest)
  con2 <- connect_quiet(dest)
  expect_identical(
    ent_snapshot_hash(con2),
    digest::digest(file = dest, algo = "sha256", serialize = FALSE)
  )
  expect_equal(DBI::dbGetQuery(con2, "SELECT count(*) AS n FROM t")$n, 2L)
  # The snapshot is self-contained: no sidecars follow the copy.
  expect_false(file.exists(paste0(dest, "-wal")))
  entropia_disconnect(con2)
  entropia_disconnect(con)
  DBI::dbDisconnect(db)
})

test_that("entropia_copy refuses to overwrite an existing dest", {
  con <- connect_quiet(ent_fixture("mini"))
  dest <- tempfile(fileext = ".sqlite")
  writeLines("x", dest)
  expect_error(entropia_copy(con, dest), class = "entropia_error_dest_exists")
  entropia_disconnect(con)
})

test_that("invalid flags and policies are rejected before file access", {
  for (value in list(NA, 1, logical(), c(TRUE, FALSE))) {
    for (arg in c("write", "validate", "quiet")) {
      args <- list(path = tempfile())
      args[[arg]] <- value
      expect_error(do.call(entropia_connect, args),
        class = "entropia_error_invalid_argument"
      )
    }
  }
  for (policy in list("w", NA_character_, c("warn", "allow"), 1)) {
    withr::with_options(list(entropiaR.schema_policy = policy), {
      expect_error(entropia_connect(tempfile(), validate = FALSE),
        class = "entropia_error_invalid_argument"
      )
    })
  }
})

test_that("post-open metadata failures disconnect the underlying connection", {
  path <- tempfile(fileext = ".sqlite")
  db <- DBI::dbConnect(RSQLite::SQLite(), path)
  DBI::dbExecute(db, "CREATE TABLE _migrations (wrong_column TEXT)")
  DBI::dbDisconnect(db)
  captured <- NULL
  original <- ent_current_version
  testthat::local_mocked_bindings(ent_current_version = function(con) {
    captured <<- con
    original(con)
  }, .package = "entropiaR")
  expect_error(entropia_connect(path, validate = FALSE), "name")
  expect_false(DBI::dbIsValid(captured))
})

test_that("entropia_connect errors on a missing file", {
  expect_error(
    entropia_connect(tempfile(fileext = ".sqlite")),
    class = "entropia_error_not_found"
  )
})

test_that("entropia_connect errors on non-SQLite files", {
  expect_error(
    entropia_connect(ent_fixture("notsqlite")),
    class = "entropia_error_not_sqlite"
  )
  expect_error(
    entropia_connect(ent_fixture("corrupt")),
    class = "entropia_error_not_sqlite"
  )
})

test_that("entropia_connect wraps a locked database", {
  src <- tempfile(fileext = ".sqlite")
  db_a <- DBI::dbConnect(RSQLite::SQLite(), src)
  DBI::dbExecute(db_a, "CREATE TABLE t (a INTEGER)")
  DBI::dbExecute(db_a, "BEGIN EXCLUSIVE")
  expect_error(entropia_connect(src), class = "entropia_error_locked")
  DBI::dbExecute(db_a, "ROLLBACK")
  DBI::dbDisconnect(db_a)
})
