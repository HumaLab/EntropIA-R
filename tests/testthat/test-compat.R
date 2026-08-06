# Tests for Task 6: compatibility layer + schema policies.
#
# Covers entropia_schema_compat()'s classification (known/unknown/older/newer),
# the options(entropiaR.schema_policy) wiring into entropia_connect, the
# required/optional column gap behavior, and the ent_sql() versioned SQL
# selector. All fixtures come from ent_fixture() (temp copies); the reference
# corpus is never opened by tests.

# Scratch DBs hand-rolled in tempdir so tests can exercise schema deviations
# the checked-in fixtures do not ship: a DB at 0001_initial whose items table
# lacks the required `title`, and a DB at 0029_rag_chunks whose collections
# table lacks the optional `description`.
scratch_db_missing_required <- function() {
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
    "CREATE TABLE items (
       id            TEXT PRIMARY KEY,
       collection_id TEXT NOT NULL,
       metadata      TEXT,
       created_at    INTEGER NOT NULL,
       updated_at    INTEGER NOT NULL)"
  )
  DBI::dbDisconnect(db)
  tmp
}

scratch_db_missing_optional <- function() {
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
       id         TEXT PRIMARY KEY,
       name       TEXT NOT NULL,
       created_at INTEGER NOT NULL,
       updated_at INTEGER NOT NULL)"
  )
  DBI::dbDisconnect(db)
  tmp
}

# --- entropia_schema_compat classification ----------------------------------

test_that("entropia_schema_compat classifies every connectable fixture", {
  expect_compat <- function(name, status, compatible = TRUE) {
    con <- ent_connect_fixture(name)
    on.exit(try(entropia_disconnect(con), silent = TRUE), add = TRUE)
    c <- entropia_schema_compat(con)
    expect_identical(c$status, status, info = name)
    expect_identical(c$compatible, compatible, info = name)
  }
  expect_compat("full", "known")
  expect_compat("legacy-seconds", "known")
  expect_compat("unknown-version", "newer")
  expect_compat("mini", "older")
  expect_compat("legacy-pre0019", "older")
})

test_that("entropia_schema_compat reports a database without migrations as unknown", {
  con <- entropia_connect(":memory:")
  on.exit(entropia_disconnect(con), add = TRUE)
  c <- entropia_schema_compat(con)
  expect_identical(c$status, "unknown")
  expect_identical(c$version, NA_character_)
  expect_true(c$compatible)
})

test_that("entropia_schema_compat separates required from optional gaps", {
  # Missing required column: incompatible, reported in required_missing.
  tmp <- scratch_db_missing_required()
  withr::with_options(list(entropiaR.schema_policy = "allow"), {
    con <- entropia_connect(tmp)
    on.exit(entropia_disconnect(con), add = TRUE)
    c <- entropia_schema_compat(con)
    expect_identical(c$status, "older") # 0001_initial < 0029_rag_chunks
    expect_false(c$compatible)
    expect_true("title" %in% c$required_missing$column)
    expect_true(all(c$required_missing$table == "items"))
  })

  # Missing optional column: compatible, reported in optional_missing.
  tmp2 <- scratch_db_missing_optional()
  withr::with_options(list(entropiaR.schema_policy = "allow"), {
    con <- entropia_connect(tmp2)
    on.exit(entropia_disconnect(con), add = TRUE)
    c <- entropia_schema_compat(con)
    expect_identical(c$status, "known")
    expect_true(c$compatible)
    expect_true("description" %in% c$optional_missing$column)
    expect_true(all(c$optional_missing$table == "collections"))
  })
})

# --- policy wiring into entropia_connect -------------------------------------

test_that("a newer (unknown-version) schema warns by default with actionable text", {
  path <- ent_fixture("unknown-version")
  withr::with_options(list(entropiaR.schema_policy = "warn"), {
    con <- NULL
    w <- expect_warning(
      con <- entropia_connect(path),
      class = "entropia_warn_schema"
    )
    expect_s4_class(con, "entropia_conn")
    msg <- conditionMessage(w)
    expect_match(msg, "newer")
    expect_match(msg, "schema_policy")
    entropia_disconnect(con)
  })
})

test_that("the error policy hard-stops on a newer (unknown-version) schema", {
  path <- ent_fixture("unknown-version")
  withr::with_options(list(entropiaR.schema_policy = "error"), {
    expect_error(
      entropia_connect(path),
      class = "entropia_error_schema_incompatible"
    )
  })
})

test_that("the allow policy connects to a newer schema silently", {
  path <- ent_fixture("unknown-version")
  withr::with_options(list(entropiaR.schema_policy = "allow"), {
    con <- NULL
    expect_silent(con <- entropia_connect(path))
    expect_s4_class(con, "entropia_conn")
    expect_identical(attr(con, "schema_version"), "0030_future_schema")
    entropia_disconnect(con)
  })
})

test_that("quiet = TRUE suppresses the default warning", {
  path <- ent_fixture("unknown-version")
  withr::with_options(list(entropiaR.schema_policy = "warn"), {
    con <- NULL
    expect_silent(con <- entropia_connect(path, quiet = TRUE))
    expect_s4_class(con, "entropia_conn")
    entropia_disconnect(con)
  })
})

test_that("a missing required column aborts with guidance under warn", {
  tmp <- scratch_db_missing_required()
  withr::with_options(list(entropiaR.schema_policy = "warn"), {
    err <- tryCatch(entropia_connect(tmp), error = function(e) e)
    expect_s3_class(err, "entropia_error_schema_incompatible")
    msg <- conditionMessage(err)
    expect_match(msg, "items\\.title")
    expect_match(msg, "schema_policy")
    # The failed open left no connection behind.
    expect_null(attr(err, "connection"))
  })
})

test_that("the allow policy proceeds even with a missing required column", {
  tmp <- scratch_db_missing_required()
  withr::with_options(list(entropiaR.schema_policy = "allow"), {
    con <- NULL
    expect_silent(con <- entropia_connect(tmp))
    expect_s4_class(con, "entropia_conn")
    entropia_disconnect(con)
  })
})

test_that("a missing optional column warns and proceeds by default", {
  tmp <- scratch_db_missing_optional()
  withr::with_options(list(entropiaR.schema_policy = "warn"), {
    con <- NULL
    w <- expect_warning(
      con <- entropia_connect(tmp),
      class = "entropia_warn_schema"
    )
    expect_s4_class(con, "entropia_conn")
    msg <- conditionMessage(w)
    expect_match(msg, "Optional")
    expect_match(msg, "collections\\.description")
    entropia_disconnect(con)
  })
})

test_that("the error policy hard-stops on any schema deviation", {
  tmp <- scratch_db_missing_optional()
  withr::with_options(list(entropiaR.schema_policy = "error"), {
    expect_error(
      entropia_connect(tmp),
      class = "entropia_error_schema_incompatible"
    )
  })
})

test_that("an older but compatible schema warns and proceeds by default", {
  path <- ent_fixture("legacy-pre0019")
  withr::with_options(list(entropiaR.schema_policy = "warn"), {
    con <- NULL
    w <- expect_warning(
      con <- entropia_connect(path),
      class = "entropia_warn_schema"
    )
    expect_s4_class(con, "entropia_conn")
    expect_match(conditionMessage(w), "older")
    entropia_disconnect(con)
  })
})

# --- message snapshots --------------------------------------------------------

test_that("schema warnings and errors have stable actionable messages", {
  path <- ent_fixture("unknown-version")
  withr::with_options(list(entropiaR.schema_policy = "warn"), {
    con <- NULL
    w <- expect_warning(con <- entropia_connect(path), class = "entropia_warn_schema")
    entropia_disconnect(con)
    expect_snapshot(conditionMessage(w))
  })

  tmp <- scratch_db_missing_required()
  withr::with_options(list(entropiaR.schema_policy = "warn"), {
    err <- tryCatch(entropia_connect(tmp), error = function(e) e)
    expect_snapshot(conditionMessage(err))
  })
})

# --- ent_sql versioned SQL selector -------------------------------------------

test_that("ent_sql selects the version-appropriate fragment", {
  # Post-0019 (reference): the target_type filter is available.
  expect_match(
    ent_sql("0029_rag_chunks", "llm_results_target"),
    "WHERE target_type = \\?target"
  )
  # Pre-0019: llm_results has no target_type; the fallback fragment is used.
  pre <- ent_sql("0018_fts_rowid_canonical", "llm_results_target")
  expect_false(grepl("target_type = \\?target", pre))
  expect_match(pre, "pre-0019")
  # Unknown version: the reference fragment is the safe default.
  expect_match(ent_sql(NA_character_, "llm_results_target"), "target_type")
  expect_match(ent_sql(NULL, "llm_results_target"), "target_type")
})

test_that("ent_sql errors for an unknown fragment id", {
  expect_error(
    ent_sql("0029_rag_chunks", "no_such_fragment"),
    class = "entropia_error_sql_fragment_missing"
  )
})
