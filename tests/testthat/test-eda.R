test_that("profile sampling is reproducible and preserves caller RNG", {
  set.seed(718)
  before <- .Random.seed
  x <- tibble::tibble(id = seq_len(30), value = seq_len(30) * 2)
  a <- entropia_profile(x, sample_n = 7, seed = 3)
  expect_identical(.Random.seed, before)
  b <- entropia_profile(x, sample_n = 7, seed = 3)
  expect_identical(a, b)
  expect_equal(length(a$sampling$row_indices), 7L)
  expect_equal(anyDuplicated(a$sampling$row_indices), 0L)
})

test_that("profile empty and nonfinite numeric values do not yield infinite ranges", {
  p <- entropia_profile(tibble::tibble(value = numeric(), when = as.Date(character())))
  expect_true(all(is.na(p$numeric$value[p$numeric$statistic %in% c("min", "max", "mean")])) )
  expect_identical(p$missing$status, c("no_data", "no_data"))
  p <- entropia_profile(tibble::tibble(value = c(NA_real_, Inf, 2), when = as.Date(c(NA, "2020-01-01", "2020-02-01"))))
  expect_equal(p$numeric$value[p$numeric$statistic == "mean"], 2)
  expect_identical(unique(p$numeric$variable), "value")
  expect_identical(p$missing$status[p$missing$variable == "value"], "invalid")
})

test_that("profile exact key duplicates differ from exact row duplicates", {
  x <- tibble::tibble(item_id = c("a", "a", "b", "b"), value = c(1, 2, 3, 3))
  p <- entropia_profile(x)
  expect_equal(p$duplicates$n, c(1, 2))
  expect_equal(p$duplicates$n_groups, c(1, 2))
  expect_equal(p$duplicates$n_rows, c(2, 4))
})

test_that("overview empty ID selection does not fall back to all items", {
  con <- ent_connect_fixture("full")
  on.exit(entropia_disconnect(con), add = TRUE)
  out <- entropia_overview(con, collection_ids = character())
  expect_true(all(out$counts$n == 0))
  expect_equal(nrow(out$collections), 0L)
  expect_equal(nrow(out$entities), 0L)
  expect_equal(nrow(out$topics), 0L)
  expect_s3_class(out$temporal$date, "POSIXct")
})

test_that("overview distinguishes malformed metadata from absent metadata", {
  path <- ent_fixture("full")
  wcon <- DBI::dbConnect(RSQLite::SQLite(), path)
  # items.search_text is GENERATED from json(metadata); dropping the derived
  # column on this private copy lets invalid JSON reach storage, which is the
  # condition under test (the read layer never touches search_text).
  DBI::dbExecute(wcon, "DROP INDEX IF EXISTS idx_items_search")
  DBI::dbExecute(wcon, "ALTER TABLE items DROP COLUMN search_text")
  DBI::dbExecute(wcon, "UPDATE items SET metadata = '{broken' WHERE id = ?",
    params = list("22222222-2222-4222-8222-222222222221"))
  DBI::dbDisconnect(wcon)
  con <- withr::with_options(
    list(entropiaR.schema_policy = "allow"),
    entropia_connect(path)
  )
  on.exit(entropia_disconnect(con), add = TRUE)
  q <- entropia_overview(con)$quality
  presence <- q[q$metric == "metadata_coverage", ]
  validity <- q[q$metric == "metadata_validity", ]
  expect_equal(sum(presence$n), 2)
  expect_equal(sum(validity$n), 1)
  expect_true("invalid" %in% validity$status)
})

test_that("quality retains collection identity rather than only its label", {
  con <- ent_connect_fixture("full")
  on.exit(entropia_disconnect(con), add = TRUE)
  q <- entropia_corpus_quality(con)
  m <- q[q$metric == "metadata_coverage", ]
  expect_identical(m$group_id, "11111111-1111-4111-8111-111111111111")
  expect_identical(m$unit, "item")
})
