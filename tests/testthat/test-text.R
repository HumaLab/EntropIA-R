# Tests for Task 15 (entropia_text).
#
# Per-asset best text: the source selection (extraction/transcription/auto)
# is one SQL expression (COALESCE for auto, the app's FTS rule) over the 1:1
# extractions/transcriptions joins; OCR page markers (![](page=n,bbox=[...]))
# are stripped in SQL via a recursive CTE so the result stays lazy. Assets
# with neither layer get NA text and are still returned.
# Fixtures come from ent_fixture() temp copies; never data-test/.

TEXT_ASSET_PDF <- "33333333-3333-4333-8333-333333333331"
TEXT_ASSET_PAGE1 <- "33333333-3333-4333-8333-333333333332"
TEXT_ASSET_PAGE2 <- "33333333-3333-4333-8333-333333333333"
TEXT_ASSET_IMG <- "33333333-3333-4333-8333-333333333334"
TEXT_ASSET_AUDIO <- "33333333-3333-4333-8333-333333333335"
TEXT_ALL_ASSETS <- c(
  TEXT_ASSET_PDF, TEXT_ASSET_PAGE1, TEXT_ASSET_PAGE2, TEXT_ASSET_IMG, TEXT_ASSET_AUDIO
)

with_text_con <- function(name, f) {
  con <- ent_connect_fixture(name)
  on.exit(try(entropia_disconnect(con), silent = TRUE), add = TRUE)
  f(con)
}

# --- laziness and shape ------------------------------------------------------

test_that("entropia_text returns a lazy tbl_sql with asset columns plus text", {
  with_text_con("full", function(con) {
    res <- entropia_text(con)
    expect_s3_class(res, "tbl_sql")
    expect_false(inherits(res, "data.frame"))
    expect_true(is.na(nrow(res)))
    expect_identical(
      as.character(dplyr::tbl_vars(res)),
      c(
        "id", "item_id", "path", "type", "size", "created_at", "sort_index",
        "parent_asset_id", "page_number", "text"
      )
    )
  })
})

test_that("auto source is one SQL COALESCE over the two text layers", {
  with_text_con("full", function(con) {
    sql <- dbplyr::sql_render(entropia_text(con, strip_markers = FALSE))
    expect_match(sql, "COALESCE")
    expect_match(sql, "LEFT JOIN")
    expect_match(sql, "extractions")
    expect_match(sql, "transcriptions")
  })
})

# --- source selection on the full fixture -------------------------------------

test_that("source = extraction returns extraction text and NA for the rest", {
  with_text_con("full", function(con) {
    res <- dplyr::collect(entropia_text(con, source = "extraction", strip_markers = FALSE))
    expect_identical(
      res$text[match(TEXT_ALL_ASSETS, res$id)],
      c(
        "![](page=1,bbox=[10,10,500,700]) La huelga general de 1920 movilizo a los obreros.",
        "Segunda pagina del manifiesto con demandas salariales.",
        NA, NA, NA
      )
    )
  })
})

test_that("source = transcription returns transcription text and NA for the rest", {
  with_text_con("full", function(con) {
    res <- dplyr::collect(entropia_text(con, source = "transcription", strip_markers = FALSE))
    expect_identical(
      res$text[match(TEXT_ALL_ASSETS, res$id)],
      c(NA, NA, NA, NA, "Compa<U+00F1>eros, a la huelga")
    )
  })
})

test_that("auto picks extraction when present, else transcription (both / one / neither)", {
  with_text_con("full", function(con) {
    res <- dplyr::collect(entropia_text(con, strip_markers = FALSE))
    expect_identical(
      res$text[match(TEXT_ALL_ASSETS, res$id)],
      c(
        "![](page=1,bbox=[10,10,500,700]) La huelga general de 1920 movilizo a los obreros.",
        "Segunda pagina del manifiesto con demandas salariales.",
        NA, NA,
        "Compa<U+00F1>eros, a la huelga"
      )
    )
  })
})

# --- marker stripping ---------------------------------------------------------

test_that("strip_markers = TRUE removes the marker, FALSE keeps it", {
  with_text_con("full", function(con) {
    stripped <- dplyr::collect(entropia_text(con)) # default strip_markers = TRUE
    raw <- dplyr::collect(entropia_text(con, strip_markers = FALSE))
    pdf_stripped <- stripped$text[match(TEXT_ASSET_PDF, stripped$id)]
    pdf_raw <- raw$text[match(TEXT_ASSET_PDF, raw$id)]
    expect_false(grepl("!\\[\\]\\(page=", pdf_stripped))
    expect_true(grepl("!\\[\\]\\(page=", pdf_raw))
    # the marker is removed exactly; the surrounding space survives
    expect_identical(pdf_stripped, " La huelga general de 1920 movilizo a los obreros.")
    # non-marker text is untouched
    expect_identical(
      stripped$text[match(TEXT_ASSET_AUDIO, stripped$id)],
      "Compa<U+00F1>eros, a la huelga"
    )
  })
})

test_that("the strip fragment removes several markers and leaves NULLs alone", {
  con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  sql <- ent_strip_markers_sql(
    c("id", "text"),
    paste0(
      "SELECT 'a' AS id, 'x ![](page=1,bbox=[10,10,500,700]) y ",
      "![](page=2,bbox=[0,0,1,1]) z' AS text ",
      "UNION ALL SELECT 'b', 'plain' ",
      "UNION ALL SELECT 'c', NULL"
    )
  )
  res <- DBI::dbGetQuery(con, sql)
  expect_identical(res$text[res$id == "a"], "x  y  z")
  expect_identical(res$text[res$id == "b"], "plain")
  expect_true(is.na(res$text[res$id == "c"]))
})

# --- empty text handling -------------------------------------------------------

test_that("assets with no text layer stay in the result with NA text", {
  with_text_con("full", function(con) {
    res <- dplyr::collect(entropia_text(con))
    expect_identical(sort(res$id), sort(TEXT_ALL_ASSETS))
    expect_identical(
      res$text[match(c(TEXT_ASSET_PAGE2, TEXT_ASSET_IMG), res$id)],
      c(NA_character_, NA_character_)
    )
  })
})

# --- the assets argument --------------------------------------------------------

test_that("a character vector of asset ids filters the result", {
  with_text_con("full", function(con) {
    res <- dplyr::collect(entropia_text(con, assets = c(TEXT_ASSET_PDF, TEXT_ASSET_AUDIO)))
    expect_identical(sort(res$id), sort(c(TEXT_ASSET_PDF, TEXT_ASSET_AUDIO)))
    expect_false(anyNA(res$text))
  })
})

test_that("a lazy table of assets is used as the base", {
  with_text_con("full", function(con) {
    audio <- dplyr::filter(entropia_assets(con), .data$type == "audio")
    res <- dplyr::collect(entropia_text(con, assets = audio))
    expect_identical(res$id, TEXT_ASSET_AUDIO)
    expect_identical(res$text, "Compa<U+00F1>eros, a la huelga")
  })
})

test_that("an invalid assets argument errors", {
  cls <- "entropia_error_invalid_argument"
  with_text_con("full", function(con) {
    expect_error(entropia_text(con, assets = 42), class = cls)
    expect_error(entropia_text(con, assets = c("x", NA_character_)), class = cls)
    expect_error(entropia_text(con, assets = ""), class = cls)
  })
})

test_that("a base with a reserved column name errors", {
  cls <- "entropia_error_invalid_argument"
  with_text_con("full", function(con) {
    bad <- dplyr::mutate(entropia_assets(con), text = .data$path)
    expect_error(entropia_text(con, assets = bad), class = cls)
  })
})

# --- argument validation ---------------------------------------------------------

test_that("entropia_text validates source and strip_markers", {
  cls <- "entropia_error_invalid_argument"
  with_text_con("full", function(con) {
    expect_error(entropia_text(con, source = "bogus"), class = cls)
    expect_error(entropia_text(con, source = NA_character_), class = cls)
    expect_error(entropia_text(con, source = c("auto", "extraction")), class = cls)
    expect_error(entropia_text(con, strip_markers = NA), class = cls)
    expect_error(entropia_text(con, strip_markers = "yes"), class = cls)
    expect_error(entropia_text(con, strip_markers = c(TRUE, FALSE)), class = cls)
  })
})

# --- legacy / error paths ----------------------------------------------------------

test_that("entropia_text raises table_missing on schemas without text tables", {
  cls <- "entropia_error_table_missing"
  with_text_con("mini", function(con) {
    expect_error(entropia_text(con), class = cls)
    expect_error(entropia_text(con, source = "extraction"), class = cls)
    expect_error(entropia_text(con, source = "transcription"), class = cls)
  })
})

test_that("entropia_text works on legacy-pre0019 and rejects a closed connection", {
  with_text_con("legacy-pre0019", function(con) {
    res <- dplyr::collect(entropia_text(con))
    expect_true("text" %in% names(res))
    # pre-0019 has the same 5 assets; text values match the full fixture
    expect_false(anyNA(res$text[match(c(TEXT_ASSET_PDF, TEXT_ASSET_AUDIO), res$id)]))
  })
  con <- withr::with_options(
    list(entropiaR.schema_policy = "allow"),
    entropia_connect(ent_fixture("full"))
  )
  entropia_disconnect(con)
  expect_error(entropia_text(con), class = "entropia_error_invalid_connection")
})
