# Tests for Task 24 (export).
#
# entropia_export() writes a data frame/tibble or a lazy tbl_sql to a file in
# csv/tsv/json/rds (always available) or parquet/arrow (arrow in Suggests).
# Lazy inputs to the delimited formats are streamed in bounded chunks
# (dbSendQuery + fetch, never collected whole); json/rds/parquet/arrow collect
# first. Lazy exports are deterministically ordered: when the rendered SQL has
# no ORDER BY the export arranges by the first column, so identical inputs
# yield byte-identical files.

EXPORT_ERR <- "entropia_error_invalid_argument"

with_export_con <- function(name, f) {
  con <- ent_connect_fixture(name)
  on.exit(try(entropia_disconnect(con), silent = TRUE), add = TRUE)
  f(con)
}

# A writable SQLite DB holding a `big` table of `n` rows inserted in reverse id
# order, so a lazy export ordered by id provably reorders relative to the
# physical row order. Returns an open (writable) connection.
with_big_table <- function(n, f) {
  path <- tempfile(fileext = ".sqlite")
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  df <- data.frame(
    id = rev(seq_len(n)),
    val = sprintf("row-%03d", rev(seq_len(n)))
  )
  DBI::dbWriteTable(con, "big", df, overwrite = TRUE)
  f(con)
}

# --- csv/tsv round-trips (materialised) --------------------------------------

test_that("csv export round-trips a materialised tibble", {
  df <- tibble::tibble(id = 1:3, label = c("a", "b", "c"), x = c(1.5, 2.5, 3.5))
  p <- tempfile(fileext = ".csv")
  expect_invisible(entropia_export(df, p, "csv"))
  expect_true(file.exists(p))
  out <- utils::read.csv(p, check.names = FALSE, stringsAsFactors = FALSE)
  expect_equal(out$id, df$id)
  expect_equal(out$label, df$label)
  expect_equal(out$x, df$x)
})

test_that("tsv export round-trips a materialised tibble", {
  df <- tibble::tibble(id = 1:2, label = c("a", "b"))
  p <- tempfile(fileext = ".tsv")
  entropia_export(df, p, "tsv")
  out <- utils::read.delim(p, check.names = FALSE, stringsAsFactors = FALSE)
  expect_equal(out$id, df$id)
  expect_equal(out$label, df$label)
})

test_that("csv export round-trips multiline text with embedded quotes", {
  # RFC-4180 quote escaping (qmethod = "double"): a field holding both a newline
  # and a double quote must survive a write/read round-trip through base R.
  df <- tibble::tibble(id = 1:2, txt = c("line1\nline2", "say \"hello\"\nworld"))
  p <- tempfile(fileext = ".csv")
  entropia_export(df, p, "csv")
  out <- utils::read.csv(p, check.names = FALSE, stringsAsFactors = FALSE)
  expect_equal(nrow(out), 2L)
  expect_identical(out$txt[1], df$txt[1])
  expect_identical(out$txt[2], df$txt[2])
})

test_that("the default format is csv", {
  p <- tempfile(fileext = ".csv")
  entropia_export(tibble::tibble(a = 1:3), p)
  out <- utils::read.csv(p, check.names = FALSE)
  expect_equal(nrow(out), 3L)
})

# --- lazy delimited export ----------------------------------------------------

test_that("lazy csv export is ordered deterministically and matches collect", {
  with_export_con("full", function(con) {
    p <- tempfile(fileext = ".csv")
    entropia_export(entropia_items(con), p, "csv")
    out <- utils::read.csv(p, check.names = FALSE, stringsAsFactors = FALSE)
    # the full fixture has 3 items; the lazy export arranges by id (first col)
    expect_equal(nrow(out), 3L)
    expect_identical(out$id, sort(out$id))
    expected <- dplyr::arrange(dplyr::collect(entropia_items(con)), .data$id)
    expect_identical(out$id, expected$id)
    raw <- readBin(p, "raw", file.info(p)$size)
    # UTF-8 <U+00ED> (U+00ED) in "Fotograf<U+00ED>a" <U+2014> independent of native encoding.
    expect_true(any(raw[-length(raw)] == as.raw(0xc3) & raw[-1] == as.raw(0xad)))
  })
})

test_that("streamed csv matches a single collected write across many chunks", {
  with_big_table(250, function(con) {
    big <- dplyr::tbl(con, "big")
    p_stream <- tempfile(fileext = ".csv")
    p_one <- tempfile(fileext = ".csv")
    # chunk_size = 13 forces ~20 fetch() rounds; the output must be byte-identical
    # to one materialised write of the same (deterministically ordered) data.
    entropia_export(big, p_stream, "csv", chunk_size = 13)
    entropia_export(
      dplyr::arrange(dplyr::collect(big), .data$id),
      p_one,
      "csv"
    )
    expect_identical(
      readLines(p_stream, warn = FALSE),
      readLines(p_one, warn = FALSE)
    )
  })
})

test_that("exporting the same lazy query twice yields identical files", {
  with_export_con("full", function(con) {
    p1 <- tempfile(fileext = ".csv")
    p2 <- tempfile(fileext = ".csv")
    entropia_export(entropia_items(con), p1, "csv")
    entropia_export(entropia_items(con), p2, "csv")
    expect_identical(readLines(p1, warn = FALSE), readLines(p2, warn = FALSE))
  })
})

test_that("exporting an empty lazy query writes only the header", {
  with_export_con("full", function(con) {
    p <- tempfile(fileext = ".csv")
    empty <- dplyr::filter(entropia_items(con), .data$id == "no-such-id")
    entropia_export(empty, p, "csv")
    lines <- readLines(p, warn = FALSE)
    expect_length(lines, 1L)
    expect_true(grepl("id", lines[1]))
  })
})

test_that("lazy tsv export streams the corpus", {
  with_export_con("full", function(con) {
    p <- tempfile(fileext = ".tsv")
    entropia_export(entropia_corpus(con), p, "tsv", chunk_size = 2)
    out <- utils::read.delim(p, check.names = FALSE, stringsAsFactors = FALSE)
    expect_equal(nrow(out), 5L) # 5 assets in the full-fixture corpus
  })
})

# --- list/BLOB flattening ------------------------------------------------------

test_that("csv export flattens list and BLOB columns", {
  df <- tibble::tibble(
    id = 1:2,
    j = list(1:2, 3:4),
    blob = list(charToRaw("ab"), charToRaw("cd"))
  )
  p <- tempfile(fileext = ".csv")
  entropia_export(df, p, "csv")
  out <- utils::read.csv(p, check.names = FALSE, stringsAsFactors = FALSE)
  expect_equal(nrow(out), 2L)
  expect_match(out$j[1], "^\\[1,2\\]$")
  expect_match(out$blob[1], "^61 62$")
})

# --- json ---------------------------------------------------------------------

test_that("json export round-trips a materialised tibble", {
  df <- tibble::tibble(id = 1:3, label = c("a", "b", "c"), x = c(1.5, NA, 3))
  p <- tempfile(fileext = ".json")
  entropia_export(df, p, "json")
  rt <- jsonlite::fromJSON(p)
  expect_s3_class(rt, "data.frame")
  expect_equal(rt$id, df$id)
  expect_equal(rt$label, df$label)
  expect_equal(rt$x, df$x)
})

test_that("json export works on a lazy query and parses back", {
  with_export_con("full", function(con) {
    p <- tempfile(fileext = ".json")
    entropia_export(entropia_items(con), p, "json")
    rt <- jsonlite::fromJSON(p)
    expect_equal(nrow(rt), 3L)
    expect_true(all(c("id", "title") %in% names(rt)))
  })
})

# --- rds -----------------------------------------------------------------------

test_that("rds export round-trips a materialised dataset with provenance", {
  with_export_con("full", function(con) {
    ds <- entropia_analysis_dataset(con, asset_type == "image", name = "img")
    p <- tempfile(fileext = ".rds")
    entropia_export(ds, p, "rds")
    rt <- readRDS(p)
    expect_identical(rt, ds)
    expect_identical(attr(rt, "entropia_prov"), attr(ds, "entropia_prov"))
  })
})

test_that("rds export of a lazy query collects the raw values", {
  with_export_con("full", function(con) {
    p <- tempfile(fileext = ".rds")
    entropia_export(entropia_items(con), p, "rds")
    rt <- readRDS(p)
    expected <- dplyr::arrange(dplyr::collect(entropia_items(con)), .data$id)
    expect_equal(rt, expected, ignore_attr = TRUE)
  })
})

# --- parquet / arrow -----------------------------------------------------------

test_that("parquet and arrow export round-trip (arrow present)", {
  skip_if_not_installed("arrow")
  with_export_con("full", function(con) {
    expected <- dplyr::arrange(dplyr::collect(entropia_items(con)), .data$id)

    pq <- tempfile(fileext = ".parquet")
    entropia_export(entropia_items(con), pq, "parquet")
    back <- arrow::read_parquet(pq)
    expect_equal(nrow(back), nrow(expected))
    expect_true(all(c("id", "title") %in% names(back)))
    expect_identical(back$id, expected$id)
    expect_identical(back$title, expected$title)

    ft <- tempfile(fileext = ".feather")
    entropia_export(entropia_items(con), ft, "arrow")
    back2 <- arrow::read_feather(ft)
    expect_equal(nrow(back2), nrow(expected))
    expect_identical(back2$title, expected$title)
  })
})

test_that("parquet/arrow raise a clear missing-dependency error without arrow", {
  # Simulate the arrow Suggests being absent by mocking the ent_arrow_available
  # seam (requireNamespace is a base function with no package-namespace binding,
  # so it cannot be mocked directly). The other formats must be unaffected.
  local_mocked_bindings(
    ent_arrow_available = function() FALSE,
    .package = "entropiaR"
  )
  df <- tibble::tibble(a = 1:2)
  for (fmt in c("parquet", "arrow")) {
    expect_error(
      entropia_export(df, tempfile(fileext = ".parquet"), fmt),
      class = "entropia_error_missing_dependency"
    )
    expect_error(
      entropia_export(df, tempfile(fileext = ".parquet"), fmt),
      "arrow",
      class = "entropia_error_missing_dependency"
    )
  }
  # the always-available formats still work with the mock active
  p <- tempfile(fileext = ".csv")
  entropia_export(df, p, "csv")
  expect_equal(nrow(utils::read.csv(p, check.names = FALSE)), 2L)
})

# --- validation ----------------------------------------------------------------

test_that("export validates format, path, x and chunk_size", {
  df <- tibble::tibble(a = 1:2)
  expect_error(entropia_export(df, tempfile(), "xlsx"), class = EXPORT_ERR)
  expect_error(entropia_export(df, c("a", "b"), "csv"), class = EXPORT_ERR)
  expect_error(entropia_export(df, NA_character_, "csv"), class = EXPORT_ERR)
  expect_error(entropia_export(1:3, tempfile(), "csv"), class = EXPORT_ERR)
  expect_error(entropia_export(list(a = 1), tempfile(), "csv"), class = EXPORT_ERR)
  expect_error(entropia_export(df, tempfile(), "csv", chunk_size = 0), class = EXPORT_ERR)
  expect_error(entropia_export(df, tempfile(), "csv", chunk_size = 1.5), class = EXPORT_ERR)
  expect_error(entropia_export(df, tempfile(), "csv", chunk_size = NA_integer_), class = EXPORT_ERR)
  expect_error(entropia_export(df, tempfile(), "csv", chunk_size = c(10, 20)), class = EXPORT_ERR)
})

test_that("export rejects a lazy query on a closed connection", {
  con <- ent_connect_fixture("full")
  q <- entropia_items(con)
  entropia_disconnect(con)
  expect_error(
    entropia_export(q, tempfile(fileext = ".csv"), "csv"),
    class = "entropia_error_invalid_connection"
  )
})
