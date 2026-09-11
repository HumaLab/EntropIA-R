# Tests for Task 17 (corpus quality helpers).
#
# entropia_ocr_coverage() and entropia_metadata_coverage() are lazy tbl_sql
# surfaces; entropia_corpus_quality() is a materialised long-form report. The
# full fixture has known gaps: assets without an extraction (pdf page 2, image,
# audio), an item without metadata (item 3), and no empty extraction texts --
# the empty-text scenario is introduced into a fixture copy (never the source
# artifact) by inserting an empty extraction. Fixtures come from ent_fixture()
# temp copies; never data-test/.

QUAL_COLL_1 <- "11111111-1111-4111-8111-111111111111"
QUAL_ITEM_1 <- "22222222-2222-4222-8222-222222222221"
QUAL_ITEM_2 <- "22222222-2222-4222-8222-222222222222"
QUAL_ITEM_3 <- "22222222-2222-4222-8222-222222222223"
QUAL_ASSET_PDF <- "33333333-3333-4333-8333-333333333331"
QUAL_ASSET_PAGE1 <- "33333333-3333-4333-8333-333333333332"
QUAL_ASSET_PAGE2 <- "33333333-3333-4333-8333-333333333333"
QUAL_ASSET_IMG <- "33333333-3333-4333-8333-333333333334"
QUAL_ASSET_AUDIO <- "33333333-3333-4333-8333-333333333335"

with_quality_con <- function(name, f) {
  con <- ent_connect_fixture(name)
  on.exit(try(entropia_disconnect(con), silent = TRUE), add = TRUE)
  f(con)
}

# --- OCR coverage: per-asset detail -------------------------------------------

test_that("entropia_ocr_coverage(by = 'asset') is a lazy per-asset table", {
  with_quality_con("full", function(con) {
    res <- entropia_ocr_coverage(con, by = "asset")
    expect_s3_class(res, "tbl_sql")
    expect_false(inherits(res, "data.frame"))
    expect_true(is.na(nrow(res)))
    expect_identical(as.character(dplyr::tbl_vars(res)), c(
      "asset_id", "item_id", "asset_type", "collection_id",
      "collection_name", "has_extraction", "text_empty"
    ))
  })
})

test_that("OCR per-asset flags match the fixture's known gaps", {
  with_quality_con("full", function(con) {
    res <- dplyr::collect(entropia_ocr_coverage(con, by = "asset"))
    expect_equal(nrow(res), 5L)
    res <- res[match(c(
      QUAL_ASSET_PDF, QUAL_ASSET_PAGE1, QUAL_ASSET_PAGE2,
      QUAL_ASSET_IMG, QUAL_ASSET_AUDIO
    ), res$asset_id), ]
    # 0/1 integers (SQLite booleans): pdf + page1 have extractions, the rest do not
    expect_identical(res$has_extraction, c(1L, 1L, 0L, 0L, 0L))
    # text_empty is NA when there is no extraction; none of the fixture texts is empty
    expect_identical(res$text_empty, c(0L, 0L, NA, NA, NA))
    expect_identical(res$asset_type, c("pdf", "pdf", "pdf", "image", "audio"))
    expect_identical(res$item_id, c(
      QUAL_ITEM_1, QUAL_ITEM_1, QUAL_ITEM_1,
      QUAL_ITEM_3, QUAL_ITEM_2
    ))
  })
})

test_that("OCR coverage grouped by collection matches fixture arithmetic", {
  with_quality_con("full", function(con) {
    # default by = "collection"
    res <- dplyr::collect(entropia_ocr_coverage(con))
    expect_equal(nrow(res), 1L)
    expect_identical(res$collection_id, QUAL_COLL_1)
    expect_identical(res$collection_name, "Archivo de prueba")
    expect_identical(res$n_assets, 5L)
    expect_identical(res$n_with_extraction, 2L)
    expect_identical(res$n_missing, 3L)
    expect_identical(res$n_empty, 0L)
    expect_equal(res$coverage, 2 / 5)
  })
})

test_that("OCR coverage grouped by item matches fixture arithmetic", {
  with_quality_con("full", function(con) {
    res <- dplyr::collect(entropia_ocr_coverage(con, by = "item"))
    expect_equal(nrow(res), 3L)
    res <- res[match(c(QUAL_ITEM_1, QUAL_ITEM_2, QUAL_ITEM_3), res$item_id), ]
    expect_identical(res$n_assets, c(3L, 1L, 1L))
    expect_identical(res$n_with_extraction, c(2L, 0L, 0L))
    expect_identical(res$n_missing, c(1L, 1L, 1L))
    expect_identical(res$n_empty, c(0L, 0L, 0L))
    expect_equal(res$coverage, c(2 / 3, 0, 0))
  })
})

test_that("OCR coverage pushes the grouping down to SQL", {
  with_quality_con("full", function(con) {
    sql <- dbplyr::sql_render(entropia_ocr_coverage(con))
    expect_match(sql, "GROUP BY")
    expect_match(sql, "collection_name")
    expect_match(sql, "LEFT JOIN")
    expect_match(sql, "extractions")
  })
})

# --- OCR coverage: empty extraction text ---------------------------------------

test_that("an empty extraction text is counted as a coverage gap", {
  path <- ent_fixture("full")
  wcon <- DBI::dbConnect(RSQLite::SQLite(), path)
  DBI::dbExecute(
    wcon,
    "INSERT INTO extractions (id, asset_id, text_content, method, confidence, created_at)
     VALUES (?, ?, '', 'ocr', 0.5, 1)",
    params = list(paste0("ext-", QUAL_ASSET_IMG), QUAL_ASSET_IMG)
  )
  DBI::dbDisconnect(wcon)

  con <- entropia_connect(path)
  on.exit(try(entropia_disconnect(con), silent = TRUE), add = TRUE)

  # per-asset: the image now has an extraction whose text is empty
  asset_view <- dplyr::collect(entropia_ocr_coverage(con, by = "asset"))
  img <- asset_view[asset_view$asset_id == QUAL_ASSET_IMG, ]
  expect_identical(img$has_extraction, 1L)
  expect_identical(img$text_empty, 1L)

  # grouped: one more extraction, one empty -> coverage unchanged at 2/5
  coll <- dplyr::collect(entropia_ocr_coverage(con))
  expect_identical(coll$n_with_extraction, 3L)
  expect_identical(coll$n_empty, 1L)
  expect_identical(coll$n_missing, 2L)
  expect_equal(coll$coverage, 2 / 5)
})

# --- Metadata coverage -----------------------------------------------------------

test_that("metadata coverage grouped by collection matches fixture arithmetic", {
  with_quality_con("full", function(con) {
    res <- dplyr::collect(entropia_metadata_coverage(con))
    expect_s3_class(entropia_metadata_coverage(con), "tbl_sql")
    expect_equal(nrow(res), 1L)
    expect_identical(res$collection_id, QUAL_COLL_1)
    expect_identical(res$collection_name, "Archivo de prueba")
    expect_identical(res$n_items, 3L)
    expect_identical(res$n_with_metadata, 2L)
    expect_identical(res$n_without_metadata, 1L)
    expect_equal(res$coverage, 2 / 3)
  })
})

test_that("metadata coverage by item exposes the missing-metadata item", {
  with_quality_con("full", function(con) {
    res <- dplyr::collect(entropia_metadata_coverage(con, by = "item"))
    expect_equal(nrow(res), 3L)
    res <- res[match(c(QUAL_ITEM_1, QUAL_ITEM_2, QUAL_ITEM_3), res$item_id), ]
    expect_identical(res$has_metadata, c(1L, 1L, 0L))
    expect_identical(res$collection_name, rep("Archivo de prueba", 3L))
  })
})

test_that("metadata coverage pushes the grouping down to SQL", {
  with_quality_con("full", function(con) {
    sql <- dbplyr::sql_render(entropia_metadata_coverage(con))
    expect_match(sql, "GROUP BY")
    expect_match(sql, "collection_name")
  })
})

# --- Combined quality report -----------------------------------------------------

test_that("entropia_corpus_quality is a deterministic long-form report", {
  with_quality_con("full", function(con) {
    q <- entropia_corpus_quality(con)
    expect_s3_class(q, "tbl_df")
    expect_identical(names(q), c("metric", "group_id", "group", "unit", "n", "total", "pct", "status"))
    expect_equal(nrow(q), 10L)

    ocr <- q[q$metric == "ocr_coverage", ]
    expect_identical(ocr$group, c("audio", "image", "pdf"))
    expect_identical(ocr$n, c(0L, 0L, 2L))
    expect_identical(ocr$total, c(1L, 1L, 3L))
    expect_equal(ocr$pct, c(0, 0, 2 / 3))

    trx <- q[q$metric == "transcription_presence", ]
    expect_identical(trx$group, c("audio", "image", "pdf"))
    expect_identical(trx$n, c(1L, 0L, 0L))
    expect_identical(trx$total, c(1L, 1L, 3L))

    meta <- q[q$metric == "metadata_coverage", ]
    expect_identical(meta$group, "Archivo de prueba")
    expect_identical(meta$n, 2L)
    expect_identical(meta$total, 3L)
    expect_equal(meta$pct, 2 / 3)

    # empty_text is NA-pct where no asset has a text layer
    empty <- q[q$metric == "empty_text", ]
    expect_identical(empty$group, c("audio", "image", "pdf"))
    expect_identical(empty$n, c(0L, 0L, 0L))
    expect_identical(empty$total, c(1L, 0L, 2L))
    expect_true(is.na(empty$pct[empty$group == "image"]))
    expect_equal(empty$pct[empty$group == "audio"], 0)
    expect_equal(empty$pct[empty$group == "pdf"], 0)

    # deterministic ordering: metric then group (lexicographic)
    expect_identical(
      q$metric,
      c(
        rep("empty_text", 3L),
        "metadata_coverage",
        rep("ocr_coverage", 3L),
        rep("transcription_presence", 3L)
      )
    )
    expect_identical(
      q$group[q$metric == "ocr_coverage"],
      c("audio", "image", "pdf")
    )
  })
})

test_that("corpus quality reports an empty text layer once one exists", {
  path <- ent_fixture("full")
  wcon <- DBI::dbConnect(RSQLite::SQLite(), path)
  DBI::dbExecute(
    wcon,
    "INSERT INTO extractions (id, asset_id, text_content, method, confidence, created_at)
     VALUES (?, ?, '', 'ocr', 0.5, 1)",
    params = list(paste0("ext-", QUAL_ASSET_IMG), QUAL_ASSET_IMG)
  )
  DBI::dbDisconnect(wcon)

  con <- entropia_connect(path)
  on.exit(try(entropia_disconnect(con), silent = TRUE), add = TRUE)
  q <- entropia_corpus_quality(con)

  ocr_img <- q[q$metric == "ocr_coverage" & q$group == "image", ]
  expect_identical(ocr_img$n, 0L) # the only image extraction is empty
  expect_identical(ocr_img$total, 1L)

  empty_img <- q[q$metric == "empty_text" & q$group == "image", ]
  expect_identical(empty_img$n, 1L)
  expect_identical(empty_img$total, 1L)
  expect_equal(empty_img$pct, 1)
})

# --- error paths and legacy -------------------------------------------------------

test_that("mini schema: metadata coverage works, OCR and report raise table_missing", {
  with_quality_con("mini", function(con) {
    m <- dplyr::collect(entropia_metadata_coverage(con))
    expect_equal(m$n_items, 3L)
    expect_equal(m$n_with_metadata, 2L)

    cls <- "entropia_error_table_missing"
    expect_error(entropia_ocr_coverage(con), class = cls)
    expect_error(entropia_ocr_coverage(con, by = "asset"), class = cls)
    expect_error(entropia_corpus_quality(con), class = cls)
  })
})

test_that("legacy-pre0019 reports the same coverage as full", {
  with_quality_con("legacy-pre0019", function(con) {
    ocr <- dplyr::collect(entropia_ocr_coverage(con))
    expect_identical(ocr$n_assets, 5L)
    expect_identical(ocr$n_with_extraction, 2L)
    meta <- dplyr::collect(entropia_metadata_coverage(con))
    expect_identical(meta$n_with_metadata, 2L)
  })
})

test_that("quality helpers validate the by argument", {
  cls <- "entropia_error_invalid_argument"
  with_quality_con("full", function(con) {
    expect_error(entropia_ocr_coverage(con, by = "bogus"), class = cls)
    expect_error(entropia_ocr_coverage(con, by = NA_character_), class = cls)
    expect_error(entropia_ocr_coverage(con, by = c("asset", "item")), class = cls)
    expect_error(entropia_metadata_coverage(con, by = 42), class = cls)
    expect_error(entropia_metadata_coverage(con, by = "asset"), class = cls)
  })
})

test_that("quality helpers reject a closed connection", {
  con <- ent_connect_fixture("full")
  entropia_disconnect(con)
  cls <- "entropia_error_invalid_connection"
  expect_error(entropia_ocr_coverage(con), class = cls)
  expect_error(entropia_metadata_coverage(con), class = cls)
  expect_error(entropia_corpus_quality(con), class = cls)
})
