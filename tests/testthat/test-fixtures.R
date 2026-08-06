# Tests for the fixture infrastructure (Task 3).
#
# These tests validate the generated SQLite fixtures and the ent_fixture /
# ent_connect_fixture helpers. They never touch data-test/entropia.sqlite.

# Expected schema head (MAX `_migrations.name`) for each connectable fixture.
fixture_versions <- function() {
  list(
    mini = "0001_initial",
    full = "0029_rag_chunks",
    "legacy-pre0019" = "0018_fts_rowid_canonical",
    "legacy-seconds" = "0029_rag_chunks",
    "unknown-version" = "0030_future_schema"
  )
}

# Open a fixture, run `f(con)`, always disconnect.
with_fixture_con <- function(name, f) {
  con <- ent_connect_fixture(name)
  on.exit(try(DBI::dbDisconnect(con), silent = TRUE), add = TRUE)
  f(con)
}

test_that("all fixture artifacts are present", {
  files <- ent_fixture_files()
  for (nm in names(files)) {
    expect_true(
      file.exists(testthat::test_path("fixtures", files[[nm]])),
      info = nm
    )
  }
})

test_that("every connectable fixture opens and reports its schema version", {
  for (nm in names(fixture_versions())) {
    v <- with_fixture_con(nm, ent_fixture_version)
    expect_identical(v, fixture_versions()[[nm]], info = nm)
  }
})

test_that("full fixture carries the complete post-0029 surface", {
  with_fixture_con("full", function(con) {
    tables <- DBI::dbListTables(con)
    for (t in c(
      "collections", "items", "assets", "extractions", "transcriptions",
      "layouts", "entities", "triples", "topics", "item_topics",
      "llm_results", "rag_conversations", "rag_messages", "rag_chunks",
      "vec_assets", "sync_meta", "sync_row_versions", "sync_conflicts",
      "app_settings", "rag_asset_embedding_state"
    )) {
      expect_true(t %in% tables, info = t)
    }
    trg <- DBI::dbGetQuery(
      con,
      "SELECT name FROM sqlite_master WHERE type = 'trigger'"
    )$name
    expect_equal(sum(grepl("^trg_sync_", trg)), 48)
    expect_equal(sum(grepl("^collection_activity_", trg)), 33)
    expect_true("target_type" %in%
      DBI::dbGetQuery(con, "PRAGMA table_info(llm_results)")$name)
  })
})

test_that("legacy-pre0019 llm_results lacks target_type; full has it", {
  pre <- with_fixture_con("legacy-pre0019", function(con) {
    DBI::dbGetQuery(con, "PRAGMA table_info(llm_results)")$name
  })
  expect_false("target_type" %in% pre)

  full <- with_fixture_con("full", function(con) {
    DBI::dbGetQuery(con, "PRAGMA table_info(llm_results)")$name
  })
  expect_true("target_type" %in% full)
})

test_that("legacy-seconds stores entity/triple timestamps in seconds", {
  sec <- with_fixture_con("legacy-seconds", function(con) {
    DBI::dbGetQuery(con, "SELECT MIN(created_at) AS v FROM entities")$v
  })
  # Epoch seconds magnitude (~1e9), well below the 1e12 ms guard.
  expect_true(sec > 1e8 && sec < 1e12)

  ms <- with_fixture_con("full", function(con) {
    DBI::dbGetQuery(con, "SELECT MIN(created_at) AS v FROM entities")$v
  })
  # Epoch milliseconds magnitude (>= 1e12).
  expect_true(ms >= 1e12)

  triple_sec <- with_fixture_con("legacy-seconds", function(con) {
    DBI::dbGetQuery(con, "SELECT MIN(created_at) AS v FROM triples")$v
  })
  expect_true(triple_sec > 1e8 && triple_sec < 1e12)
})

test_that("corrupt and non-SQLite fixtures are not readable databases", {
  open_and_probe <- function(name) {
    # dbConnect on a non-database file emits a benign 'synchronous mode'
    # warning before the first query fails; suppress it to keep output clean.
    con <- suppressWarnings(ent_connect_fixture(name))
    on.exit(try(DBI::dbDisconnect(con), silent = TRUE), add = TRUE)
    DBI::dbGetQuery(con, "SELECT name FROM sqlite_master LIMIT 1")
  }
  expect_error(open_and_probe("corrupt"))
  expect_error(open_and_probe("notsqlite"))
})

test_that("ent_fixture hands out an isolated, writable copy", {
  src <- testthat::test_path("fixtures", "mini.sqlite")
  before <- readBin(src, "raw", n = file.size(src))

  copy <- ent_fixture("mini")
  expect_true(file.exists(copy))
  expect_false(identical(normalizePath(copy), normalizePath(src)))

  con <- DBI::dbConnect(RSQLite::SQLite(), copy)
  n0 <- DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM collections")$n
  DBI::dbExecute(
    con,
    "INSERT INTO collections (id, name, created_at, updated_at)
     VALUES ('temp-collection', 'tmp', 1, 1)"
  )
  n1 <- DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM collections")$n
  DBI::dbDisconnect(con)
  expect_equal(n1, n0 + 1)

  after <- readBin(src, "raw", n = file.size(src))
  expect_identical(before, after)
})

test_that("ent_fixture rejects unknown fixture names", {
  expect_error(ent_fixture("does-not-exist"), "Unknown fixture")
})
