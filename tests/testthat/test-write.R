# Tests for Task 25 (v2 write stubs).
#
# entropiaR v1 is read-only. The four write verbs exist as v2-contract stubs:
# every call aborts with entropia_error_write_disabled and actionable v2
# guidance, and entropia_connect(path, write = TRUE) rejects the request at the
# door with the same class. The parquet/arrow missing-dependency error path is
# covered in test-export.R; the positive parquet/arrow round-trips live there
# too (gated on arrow being installed).

WRITE_ERR <- "entropia_error_write_disabled"

test_that("every write stub aborts with entropia_error_write_disabled", {
  con <- ent_connect_fixture("full")
  on.exit(try(entropia_disconnect(con), silent = TRUE), add = TRUE)
  df <- tibble::tibble(id = "x")

  expect_error(entropia_insert(con, "items", df), class = WRITE_ERR)
  expect_error(entropia_update(con, "items", df, by = "id"), class = WRITE_ERR)
  expect_error(entropia_upsert(con, "items", df, by = "id"), class = WRITE_ERR)
  expect_error(
    entropia_delete(con, "items", filter = df$id == "x"),
    class = WRITE_ERR
  )
})

test_that("write stubs fail hard even without a live connection", {
  # v1 offers no write surface at all, so the stub does not attempt to touch the
  # connection: the operation is impossible regardless of its validity.
  expect_error(entropia_insert(NULL, "items", NULL), class = WRITE_ERR)
  expect_error(entropia_update("not-a-con", "items", NULL, by = "id"),
               class = WRITE_ERR)
  expect_error(entropia_upsert(1:3, "items", NULL, by = "id"), class = WRITE_ERR)
  expect_error(entropia_delete(NULL, "items"), class = WRITE_ERR)
})

test_that("write stub messages carry actionable v2 guidance", {
  expect_error(
    entropia_insert(NULL, "items", NULL),
    "not available",
    class = WRITE_ERR
  )
  # the message names the read-only posture, the v2 open verb and the design doc
  expect_error(
    entropia_update(NULL, "items", NULL, by = "id"),
    "read-only",
    class = WRITE_ERR
  )
  expect_error(
    entropia_upsert(NULL, "items", NULL, by = "id"),
    "v2",
    class = WRITE_ERR
  )
  expect_error(
    entropia_delete(NULL, "items"),
    "administration.Rmd",
    class = WRITE_ERR
  )
})

test_that("the stub message text is stable and per-verb", {
  con <- ent_connect_fixture("full")
  on.exit(try(entropia_disconnect(con), silent = TRUE), add = TRUE)
  e <- tryCatch(entropia_insert(con, "items", data.frame(id = "x")),
                error = function(e) e)
  expect_s3_class(e, "entropia_error_write_disabled")
  msg <- conditionMessage(e)
  expect_match(msg, "entropia_insert")
  expect_match(msg, "write = TRUE")
  expect_match(msg, "read-only")
})

test_that("entropia_connect(write = TRUE) rejects with the same class", {
  p <- ent_fixture("mini")
  expect_error(entropia_connect(p, write = TRUE), class = WRITE_ERR)
  # the rejection happens before any open attempt: the fixture copy is untouched
  expect_error(
    entropia_connect(p, write = TRUE),
    "read-only",
    class = WRITE_ERR
  )
})

test_that("the write stubs are exported and documented", {
  ns <- asNamespace("entropiaR")
  for (fn in c("entropia_insert", "entropia_update", "entropia_upsert",
               "entropia_delete")) {
    expect_true(exists(fn, envir = ns, inherits = FALSE),
                info = fn)
    expect_true("function" %in% class(get(fn, envir = ns)),
                info = fn)
  }
})
