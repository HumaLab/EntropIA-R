test_that("temporal floors pre-epoch dates and handles every empty unit", {
  x <- tibble::tibble(t = as.POSIXct(c(-0.5, NA_real_), origin = "1970-01-01", tz = "UTC"))
  for (u in c("second", "minute", "hour")) {
    p <- entropia_temporal_profile(x, t, unit = u)
    expected <- switch(u,
      second = -1,
      minute = -60,
      hour = -3600
    )
    expect_equal(as.numeric(p$t), expected)
    expect_equal(attr(p, "excluded"), 1)
  }
  for (u in c("second", "minute", "hour", "day", "week", "month", "quarter", "year")) {
    p <- entropia_temporal_profile(x[FALSE, ], t, unit = u)
    expect_equal(nrow(p), 0L)
    expect_s3_class(p$t, "POSIXct")
  }
})

test_that("equal collection labels do not merge distinct IDs", {
  x <- tibble::tibble(collection_id = c("a", "b"), collection_name = c("same", "same"), item_id = 1:2)
  p <- entropia_compare_collections(x)
  expect_identical(p$collection_id, c("a", "b"))
  expect_identical(p$n_items, c(1L, 1L))
})

test_that("derived data provenance does not claim the origin query", {
  con <- ent_connect_fixture("full")
  on.exit(entropia_disconnect(con), add = TRUE)
  x <- entropia_analysis_dataset(con)
  original <- entropia_provenance(x)
  y <- x[rev(seq_len(nrow(x))), ]
  attr(y, "entropia_prov") <- attr(x, "entropia_prov")
  p <- entropia_provenance(y)
  expect_identical(p$scope, "derived")
  expect_null(p$query)
  expect_identical(p$origin$query, original$query)
  expect_identical(p$origin$dataset_sha256, original$dataset_sha256)
  expect_false(identical(p$dataset_sha256, original$dataset_sha256))
  path <- tempfile()
  entropia_write_provenance(y, path, redact = TRUE)
  rt <- jsonlite::fromJSON(path)
  expect_null(rt$source_path)
  expect_null(rt$origin$query)
})

test_that("item projection rejects asset ambiguity and empty selection stays typed", {
  con <- ent_connect_fixture("full")
  on.exit(entropia_disconnect(con), add = TRUE)
  expect_error(entropia_analysis_dataset(con, unit = "item", columns = "asset_id"),
    class = "entropia_error_invalid_argument"
  )
  x <- entropia_analysis_dataset(con, unit = "item", text = FALSE)
  expect_equal(nrow(x), length(unique(x$item_id)))
  expect_false("asset_id" %in% names(x))
  z <- entropia_analysis_dataset(con,
    collection_ids = character(), text = FALSE,
    columns = c("item_id", "item_created_at")
  )
  expect_equal(nrow(z), 0L)
  expect_s3_class(z$item_created_at, "POSIXct")
})

test_that("lazy exports break third-column ties while retaining descending order", {
  con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  DBI::dbWriteTable(con, "ties", data.frame(a = c(1, 1, 2), b = 1, c = c("ñ", "á", "é")))
  q <- dplyr::arrange(dplyr::tbl(con, "ties"), dplyr::desc(.data$a))
  path <- tempfile()
  entropia_export(q, path, chunk_size = 1L)
  out <- utils::read.csv(path)
  expect_equal(out$a, c(2L, 1L, 1L))
  raw <- readBin(path, "raw", file.info(path)$size)
  # UTF-8 é (U+00E9) written as bytes, not a <U+00E9> escape.
  expect_true(any(raw[-length(raw)] == as.raw(0xc3) & raw[-1] == as.raw(0xa9)))
})
