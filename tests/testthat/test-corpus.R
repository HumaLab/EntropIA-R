# Tests for Task 16 (entropia_corpus + entropia_metadata).
#
# entropia_corpus() is the lazy workhorse: items ⋈ collections ⋈ assets, one
# row per asset, with an optional per-asset text column assembled in SQL
# (COALESCE for auto, the app's FTS rule). Filters push down to SQL and the
# page_assets toggle excludes PDF page assets. entropia_metadata() parses
# items.metadata into tidy rows (original_name/path/imported_at + list-columns).
# Fixtures come from ent_fixture() temp copies; never data-test/.

CORPUS_COLL_1 <- "11111111-1111-4111-8111-111111111111"
CORPUS_ITEM_1 <- "22222222-2222-4222-8222-222222222221"
CORPUS_ITEM_2 <- "22222222-2222-4222-8222-222222222222"
CORPUS_ITEM_3 <- "22222222-2222-4222-8222-222222222223"
CORPUS_ASSET_PDF <- "33333333-3333-4333-8333-333333333331"
CORPUS_ASSET_PAGE1 <- "33333333-3333-4333-8333-333333333332"
CORPUS_ASSET_PAGE2 <- "33333333-3333-4333-8333-333333333333"
CORPUS_ASSET_IMG <- "33333333-3333-4333-8333-333333333334"
CORPUS_ASSET_AUDIO <- "33333333-3333-4333-8333-333333333335"
CORPUS_ALL_ASSETS <- c(
  CORPUS_ASSET_PDF, CORPUS_ASSET_PAGE1, CORPUS_ASSET_PAGE2,
  CORPUS_ASSET_IMG, CORPUS_ASSET_AUDIO
)

with_corpus_con <- function(name, f) {
  con <- ent_connect_fixture(name)
  on.exit(try(entropia_disconnect(con), silent = TRUE), add = TRUE)
  f(con)
}

# --- laziness and shape ------------------------------------------------------

test_that("entropia_corpus returns a lazy tbl_sql with the expected columns", {
  with_corpus_con("full", function(con) {
    res <- entropia_corpus(con)
    expect_s3_class(res, "tbl_sql")
    expect_false(inherits(res, "data.frame"))
    expect_true(is.na(nrow(res)))
    expect_identical(as.character(dplyr::tbl_vars(res)), c(
      "item_id", "item_title", "collection_id", "metadata",
      "item_created_at", "item_updated_at",
      "collection_name", "collection_description",
      "collection_created_at", "collection_updated_at",
      "asset_id", "asset_path", "asset_type", "asset_size",
      "asset_created_at", "asset_sort_index",
      "parent_asset_id", "page_number", "text"
    ))
  })
})

test_that("corpus join keeps one row per asset (no fan-out)", {
  with_corpus_con("full", function(con) {
    res <- dplyr::collect(entropia_corpus(con))
    expect_equal(nrow(res), 5L)
    expect_identical(sort(res$asset_id), sort(CORPUS_ALL_ASSETS))
    expect_identical(anyDuplicated(res$asset_id), 0L)
    # no BLOB columns in the corpus
    expect_false(any(c("embedding") %in% names(res)))
  })
})

# --- text layer ----------------------------------------------------------------

test_that("auto text is one SQL COALESCE over the two text layers", {
  with_corpus_con("full", function(con) {
    sql <- dbplyr::sql_render(entropia_corpus(con))
    expect_match(sql, "COALESCE")
    expect_match(sql, "LEFT JOIN")
    expect_match(sql, "extractions")
    expect_match(sql, "transcriptions")
  })
})

test_that("corpus text follows the auto rule (extraction else transcription)", {
  with_corpus_con("full", function(con) {
    res <- dplyr::collect(entropia_corpus(con))
    txt <- res$text[match(CORPUS_ALL_ASSETS, res$asset_id)]
    expect_identical(txt, c(
      "![](page=1,bbox=[10,10,500,700]) La huelga general de 1920 movilizo a los obreros.",
      "Segunda pagina del manifiesto con demandas salariales.",
      NA_character_, NA_character_,
      "Compañeros, a la huelga"
    ))
  })
})

test_that("text = FALSE omits the text column; explicit sources select one layer", {
  with_corpus_con("full", function(con) {
    no_text <- entropia_corpus(con, text = FALSE)
    expect_false("text" %in% dplyr::tbl_vars(no_text))
    expect_equal(nrow(dplyr::collect(no_text)), 5L)

    ext <- dplyr::collect(entropia_corpus(con, text = "extraction"))
    expect_identical(
      ext$text[match(c(CORPUS_ASSET_PDF, CORPUS_ASSET_AUDIO), ext$asset_id)],
      c(
        "![](page=1,bbox=[10,10,500,700]) La huelga general de 1920 movilizo a los obreros.",
        NA_character_
      )
    )

    trx <- dplyr::collect(entropia_corpus(con, text = "transcription"))
    expect_identical(
      trx$text[match(c(CORPUS_ASSET_PDF, CORPUS_ASSET_AUDIO), trx$asset_id)],
      c(NA_character_, "Compañeros, a la huelga")
    )
  })
})

# --- filters push down to SQL ---------------------------------------------------

test_that("collections and asset_types filters push down to SQL", {
  with_corpus_con("full", function(con) {
    res <- entropia_corpus(con, collections = "Archivo de prueba")
    sql <- dbplyr::sql_render(res)
    expect_match(sql, "collection_name")
    expect_match(sql, "Archivo de prueba")
    expect_equal(nrow(dplyr::collect(res)), 5L)

    audio <- entropia_corpus(con, asset_types = "audio")
    expect_match(dbplyr::sql_render(audio), "asset_type")
    expect_identical(dplyr::collect(audio)$asset_id, CORPUS_ASSET_AUDIO)

    pdf_audio <- entropia_corpus(con, asset_types = c("pdf", "audio"))
    expect_equal(nrow(dplyr::collect(pdf_audio)), 4L)
    # a name that matches nothing yields an empty corpus (dplyr semantics)
    expect_equal(nrow(dplyr::collect(entropia_corpus(con, collections = "Nope"))), 0L)
  })
})

test_that("page_assets = FALSE excludes PDF page assets", {
  with_corpus_con("full", function(con) {
    all_ <- dplyr::collect(entropia_corpus(con))
    top <- dplyr::collect(entropia_corpus(con, page_assets = FALSE))
    expect_equal(nrow(all_), 5L)
    expect_equal(nrow(top), 3L)
    expect_identical(
      sort(top$asset_id),
      sort(c(CORPUS_ASSET_PDF, CORPUS_ASSET_IMG, CORPUS_ASSET_AUDIO))
    )
    expect_identical(
      sort(setdiff(all_$asset_id, top$asset_id)),
      sort(c(CORPUS_ASSET_PAGE1, CORPUS_ASSET_PAGE2))
    )
  })
})

# --- context columns ------------------------------------------------------------

test_that("corpus carries the collection name and the raw item metadata", {
  with_corpus_con("full", function(con) {
    res <- dplyr::collect(entropia_corpus(con))
    expect_true(all(res$collection_name == "Archivo de prueba"))
    expect_true(all(res$collection_id == CORPUS_COLL_1))
    expect_true(is.character(res$metadata))
    expect_match(res$metadata[match(CORPUS_ASSET_PDF, res$asset_id)], "manifiesto.pdf")
    expect_match(res$metadata[match(CORPUS_ASSET_AUDIO, res$asset_id)], "carta.mp3")
    expect_true(is.na(res$metadata[match(CORPUS_ASSET_IMG, res$asset_id)]))
  })
})

# --- argument validation ---------------------------------------------------------

test_that("entropia_corpus validates its arguments", {
  cls <- "entropia_error_invalid_argument"
  with_corpus_con("full", function(con) {
    expect_error(entropia_corpus(con, text = "bogus"), class = cls)
    expect_error(entropia_corpus(con, text = NA_character_), class = cls)
    expect_error(entropia_corpus(con, collections = c("a", NA)), class = cls)
    expect_error(entropia_corpus(con, collections = ""), class = cls)
    expect_error(entropia_corpus(con, collections = 42), class = cls)
    expect_error(entropia_corpus(con, asset_types = 42), class = cls)
    expect_error(entropia_corpus(con, page_assets = NA), class = cls)
    expect_error(entropia_corpus(con, include_deleted = "yes"), class = cls)
  })
})

# --- metadata --------------------------------------------------------------------

test_that("entropia_metadata parses __entropia_file_metadata into tidy rows", {
  with_corpus_con("full", function(con) {
    m <- entropia_metadata(con)
    expect_s3_class(m, "tbl_df")
    expect_identical(names(m), c(
      "item_id", "original_name", "original_path", "imported_at", "page_count"
    ))
    expect_equal(nrow(m), 3L)
    expect_identical(
      m$original_name,
      c("manifiesto.pdf", "carta.mp3", NA_character_)
    )
    expect_identical(
      m$original_path,
      c("/docs/manifiesto.pdf", "/docs/carta.mp3", NA_character_)
    )
    expect_s3_class(m$imported_at, "POSIXct")
    expect_equal(
      m$imported_at,
      as.POSIXct(c("2026-01-15 12:05:00", "2026-01-15 12:06:00", NA), tz = "UTC")
    )
  })
})

test_that("remaining top-level metadata keys become list-columns", {
  with_corpus_con("full", function(con) {
    m <- entropia_metadata(con)
    expect_true(is.list(m$page_count))
    expect_equal(m$page_count[[1]], 2L)  # item 1 has page_count = 2
    expect_null(m$page_count[[2]])       # item 2 has no extra keys
    expect_null(m$page_count[[3]])       # item 3 has no metadata at all
  })
})

test_that("items without metadata yield an NA row", {
  with_corpus_con("full", function(con) {
    m <- entropia_metadata(con)
    third <- m[m$item_id == CORPUS_ITEM_3, ]
    expect_equal(nrow(third), 1L)
    expect_true(is.na(third$original_name))
    expect_true(is.na(third$original_path))
    expect_true(is.na(third$imported_at))
  })
})

test_that("parse = FALSE returns the raw metadata column", {
  with_corpus_con("full", function(con) {
    m <- entropia_metadata(con, parse = FALSE)
    expect_identical(names(m), c("item_id", "metadata"))
    expect_true(is.character(m$metadata))
    expect_match(m$metadata[m$item_id == CORPUS_ITEM_1], "manifiesto.pdf")
    expect_true(is.na(m$metadata[m$item_id == CORPUS_ITEM_3]))
  })
})

test_that("entropia_metadata filters by item ids and lazy item tables", {
  with_corpus_con("full", function(con) {
    m1 <- entropia_metadata(con, items = CORPUS_ITEM_1)
    expect_equal(nrow(m1), 1L)
    expect_identical(m1$item_id, CORPUS_ITEM_1)
    expect_identical(m1$original_name, "manifiesto.pdf")

    lazy <- dplyr::filter(
      entropia_items(con),
      .data$collection_id == CORPUS_COLL_1
    )
    m2 <- entropia_metadata(con, items = lazy)
    expect_equal(nrow(m2), 3L)
  })
})

test_that("entropia_metadata validates parse and items", {
  cls <- "entropia_error_invalid_argument"
  with_corpus_con("full", function(con) {
    expect_error(entropia_metadata(con, parse = NA), class = cls)
    expect_error(entropia_metadata(con, parse = "yes"), class = cls)
    expect_error(entropia_metadata(con, items = 42), class = cls)
    expect_error(entropia_metadata(con, items = c("x", NA)), class = cls)
    expect_error(entropia_metadata(con, items = c("", "y")), class = cls)
  })
})

# --- legacy / error paths ----------------------------------------------------------

test_that("corpus raises table_missing for text layers on schemas without them", {
  cls <- "entropia_error_table_missing"
  with_corpus_con("mini", function(con) {
    expect_error(entropia_corpus(con), class = cls)
    expect_error(entropia_corpus(con, text = "extraction"), class = cls)
    expect_error(entropia_corpus(con, text = "transcription"), class = cls)
    # with text = FALSE the structural join works; mini has no seeded assets,
    # so the left joins keep one row per item with NA asset columns
    res <- dplyr::collect(entropia_corpus(con, text = FALSE))
    expect_equal(nrow(res), 3L)
    expect_true(all(is.na(res$asset_id)))
  })
})

test_that("corpus degrades on schemas without the page columns", {
  # mini uses the pre-0024 assets shape (no parent_asset_id/page_number)
  with_corpus_con("mini", function(con) {
    res <- entropia_corpus(con, text = FALSE)
    vars <- dplyr::tbl_vars(res)
    expect_false("parent_asset_id" %in% vars)
    expect_false("page_number" %in% vars)
    # page_assets = FALSE is a no-op when the columns are absent
    expect_equal(nrow(dplyr::collect(entropia_corpus(con, text = FALSE, page_assets = FALSE))), 3L)
  })
})

test_that("corpus and metadata work on legacy-pre0019", {
  with_corpus_con("legacy-pre0019", function(con) {
    res <- dplyr::collect(entropia_corpus(con))
    expect_equal(nrow(res), 5L)
    expect_true(all(c("asset_id", "text", "collection_name") %in% names(res)))
    m <- entropia_metadata(con)
    expect_equal(nrow(m), 3L)
    expect_equal(m$original_name[1], "manifiesto.pdf")
  })
})

test_that("corpus and metadata reject a closed connection", {
  con <- withr::with_options(
    list(entropiaR.schema_policy = "allow"),
    entropia_connect(ent_fixture("full"))
  )
  entropia_disconnect(con)
  expect_error(entropia_corpus(con), class = "entropia_error_invalid_connection")
  expect_error(entropia_metadata(con), class = "entropia_error_invalid_connection")
})
