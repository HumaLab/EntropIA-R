# Tests for Task 9 (core accessors) and Task 10 (text accessors).
#
# Each accessor returns a lazy tbl_sql over its raw table; assets exposes the
# PDF page columns (parent_asset_id/page_number) and never selects BLOBs.
# The text accessors (extractions/transcriptions/layouts) carry deterministic
# ids (ext-|trx-|lay- + asset_id), a UNIQUE(asset_id) 1:1 contract with assets,
# and JSON-in-TEXT columns that entropia_collect() turns into list-columns.
# All fixtures come from ent_fixture() (temp copies); never data-test/.

with_tables_con <- function(name, f) {
  con <- ent_connect_fixture(name)
  on.exit(try(entropia_disconnect(con), silent = TRUE), add = TRUE)
  f(con)
}

# --- laziness ---------------------------------------------------------------

test_that("core accessors are lazy tbl_sql over their raw table", {
  with_tables_con("full", function(con) {
    coll <- entropia_collections(con)
    items <- entropia_items(con)
    assets <- entropia_assets(con)
    expect_s3_class(coll, "tbl_sql")
    expect_s3_class(items, "tbl_sql")
    expect_s3_class(assets, "tbl_sql")
    expect_match(dbplyr::sql_render(coll), "collections")
    expect_match(dbplyr::sql_render(items), "items")
    expect_match(dbplyr::sql_render(assets), "assets")
    # Lazy: nothing is materialised at access time.
    expect_false(inherits(coll, "data.frame"))
    expect_false(inherits(items, "data.frame"))
    expect_false(inherits(assets, "data.frame"))
  })
})

test_that("row count requires collect (nrow on the lazy object is NA)", {
  with_tables_con("full", function(con) {
    expect_true(is.na(nrow(entropia_collections(con))))
    expect_true(is.na(nrow(entropia_items(con))))
    expect_true(is.na(nrow(entropia_assets(con))))
    # Collecting gives the fixture's real counts (1 collection, 3 items,
    # 5 assets: pdf parent + 2 pages + image + audio).
    expect_equal(nrow(dplyr::collect(entropia_collections(con))), 1L)
    expect_equal(nrow(dplyr::collect(entropia_items(con))), 3L)
    expect_equal(nrow(dplyr::collect(entropia_assets(con))), 5L)
  })
})

test_that("accessor columns match the manifest contract", {
  with_tables_con("full", function(con) {
    mf <- ent_manifest()
    for (t in c("collections", "items", "assets")) {
      got <- as.vector(dplyr::tbl_vars(ent_tbl(con, t)))
      want <- names(mf$tables[[t]]$columns)
      expect_identical(got, want, info = t)
    }
  })
})

test_that("assets exposes the PDF page columns and no BLOB columns", {
  with_tables_con("full", function(con) {
    out <- dplyr::collect(entropia_assets(con))
    expect_true(all(c("parent_asset_id", "page_number") %in% names(out)))
    # The accessor never selects a BLOB column.
    expect_false(any(grepl("embedding|vector|^blob", names(out))))
    # Raw lazy data: page columns come back as integers.
    expect_type(out$page_number, "integer")
  })
})

# --- PDF page parent/child join ---------------------------------------------

test_that("PDF pages join to their parent asset (partial UNIQUE respected)", {
  with_tables_con("full", function(con) {
    pages <- entropia_assets(con) |>
      dplyr::filter(!is.na(parent_asset_id))
    parents <- entropia_assets(con) |>
      dplyr::select(id, type) |>
      dplyr::rename(parent_type = type)
    joined <- dplyr::left_join(pages, parents, by = c("parent_asset_id" = "id"))
    sql <- dbplyr::sql_render(joined)
    expect_match(sql, "JOIN")
    expect_match(sql, "parent_asset_id")

    out <- dplyr::collect(joined)
    expect_equal(nrow(out), 2L) # the two pdf pages
    expect_true(all(out$parent_type == "pdf"))
    # Partial UNIQUE (parent_asset_id, page_number): every parent has at most
    # one page per number.
    expect_false(any(duplicated(out[c("parent_asset_id", "page_number")])))
    expect_setequal(out$page_number, c(1L, 2L))
    # Every parent reference resolves to an existing asset.
    all_assets <- dplyr::collect(entropia_assets(con))
    expect_true(all(out$parent_asset_id %in% all_assets$id))
  })
})

# --- SQL push-down (acceptance) ---------------------------------------------

test_that("items filter pushes down to SQL and returns expected rows", {
  with_tables_con("full", function(con) {
    flt <- entropia_items(con) |>
      dplyr::filter(collection_id == "11111111-1111-4111-8111-111111111111")
    sql <- dbplyr::sql_render(flt)
    expect_match(sql, "WHERE")
    expect_match(sql, "collection_id")
    out <- dplyr::collect(flt)
    expect_equal(nrow(out), 3L)
    expect_true(all(out$collection_id == "11111111-1111-4111-8111-111111111111"))
  })
})

# --- legacy / error paths ----------------------------------------------------

test_that("assets accessor degrades gracefully on a pre-0024 schema", {
  with_tables_con("mini", function(con) {
    a <- entropia_assets(con)
    vars <- as.vector(dplyr::tbl_vars(a))
    expect_false("parent_asset_id" %in% vars)
    expect_false("page_number" %in% vars)
    expect_equal(nrow(dplyr::collect(a)), 0L)
  })
})

test_that("core accessors raise entropia_error_table_missing on absent tables", {
  con <- entropia_connect(":memory:")
  on.exit(entropia_disconnect(con), add = TRUE)
  expect_error(entropia_collections(con), class = "entropia_error_table_missing")
  expect_error(entropia_items(con), class = "entropia_error_table_missing")
  expect_error(entropia_assets(con), class = "entropia_error_table_missing")
})

test_that("core accessors reject a closed connection", {
  con <- withr::with_options(
    list(entropiaR.schema_policy = "allow"),
    entropia_connect(ent_fixture("full"))
  )
  entropia_disconnect(con)
  expect_error(entropia_collections(con), class = "entropia_error_invalid_connection")
  expect_error(entropia_items(con), class = "entropia_error_invalid_connection")
  expect_error(entropia_assets(con), class = "entropia_error_invalid_connection")
})

# --- Task 10: text accessors (extractions, transcriptions, layouts) ---------

test_that("text accessors are lazy tbl_sql over their raw table", {
  with_tables_con("full", function(con) {
    ext <- entropia_extractions(con)
    trx <- entropia_transcriptions(con)
    lay <- entropia_layouts(con)
    for (t in list(ext, trx, lay)) {
      expect_s3_class(t, "tbl_sql")
      expect_false(inherits(t, "data.frame"))
      expect_true(is.na(nrow(t)))
    }
    expect_match(dbplyr::sql_render(ext), "extractions")
    expect_match(dbplyr::sql_render(trx), "transcriptions")
    expect_match(dbplyr::sql_render(lay), "layouts")
  })
})

test_that("text accessor row counts match the full fixture", {
  with_tables_con("full", function(con) {
    expect_equal(nrow(dplyr::collect(entropia_extractions(con))), 2L)
    expect_equal(nrow(dplyr::collect(entropia_transcriptions(con))), 1L)
    expect_equal(nrow(dplyr::collect(entropia_layouts(con))), 1L)
  })
})

test_that("text accessor columns match the manifest contract", {
  with_tables_con("full", function(con) {
    mf <- ent_manifest()
    for (t in c("extractions", "transcriptions", "layouts")) {
      got <- as.vector(dplyr::tbl_vars(ent_tbl(con, t)))
      want <- names(mf$tables[[t]]$columns)
      expect_identical(got, want, info = t)
    }
  })
})

test_that("deterministic ids are derivable from asset_id (ext-|trx-|lay-)", {
  with_tables_con("full", function(con) {
    ext <- dplyr::collect(entropia_extractions(con))
    trx <- dplyr::collect(entropia_transcriptions(con))
    lay <- dplyr::collect(entropia_layouts(con))
    expect_identical(ext$id, paste0("ext-", ext$asset_id))
    expect_identical(trx$id, paste0("trx-", trx$asset_id))
    expect_identical(lay$id, paste0("lay-", lay$asset_id))
  })
})

test_that("UNIQUE(asset_id) is reflected: at most one row per asset", {
  with_tables_con("full", function(con) {
    expect_identical(anyDuplicated(dplyr::collect(entropia_extractions(con))$asset_id), 0L)
    expect_identical(anyDuplicated(dplyr::collect(entropia_transcriptions(con))$asset_id), 0L)
    expect_identical(anyDuplicated(dplyr::collect(entropia_layouts(con))$asset_id), 0L)
  })
})

test_that("text tables join 1:1 to assets on the full fixture (no fan-out)", {
  with_tables_con("full", function(con) {
    assets <- dplyr::collect(entropia_assets(con))
    ext <- dplyr::collect(entropia_extractions(con))
    trx <- dplyr::collect(entropia_transcriptions(con))
    lay <- dplyr::collect(entropia_layouts(con))
    # every referenced asset exists (no broken conceptual FK)
    expect_true(all(ext$asset_id %in% assets$id))
    expect_true(all(trx$asset_id %in% assets$id))
    expect_true(all(lay$asset_id %in% assets$id))
    # inner join keeps the row count: no fan-out from layouts/extractions
    # (assets is keyed by `id`; the conceptual FK is assets.id <- table.asset_id)
    j_ext <- dplyr::collect(dplyr::inner_join(
      entropia_extractions(con), entropia_assets(con), by = c("asset_id" = "id")
    ))
    j_trx <- dplyr::collect(dplyr::inner_join(
      entropia_transcriptions(con), entropia_assets(con), by = c("asset_id" = "id")
    ))
    j_lay <- dplyr::collect(dplyr::inner_join(
      entropia_layouts(con), entropia_assets(con), by = c("asset_id" = "id")
    ))
    expect_equal(nrow(j_ext), nrow(ext))
    expect_equal(nrow(j_trx), nrow(trx))
    expect_equal(nrow(j_lay), nrow(lay))
  })
})

test_that("entropia_collect parses JSON columns into list-columns", {
  with_tables_con("full", function(con) {
    trx <- entropia_collect(entropia_transcriptions(con))
    expect_true(is.list(trx$segments))
    seg <- trx$segments[[1]]
    expect_true(is.data.frame(seg))
    expect_named(seg, c("start_ms", "end_ms", "text"))
    expect_equal(nrow(seg), 2L)

    lay <- entropia_collect(entropia_layouts(con))
    expect_true(is.list(lay$regions))
    expect_true(is.list(lay$blocks))
    expect_true(is.data.frame(lay$regions[[1]]))
    expect_true(is.data.frame(lay$blocks[[1]]))

    # created_at (epoch ms) becomes POSIXct
    expect_s3_class(trx$created_at, "POSIXct")
    expect_s3_class(lay$created_at, "POSIXct")
  })
})

test_that("entropia_collect applies the contract to filtered lazy queries", {
  with_tables_con("full", function(con) {
    trx <- entropia_transcriptions(con) |>
      dplyr::filter(language == "es")
    out <- entropia_collect(trx)
    expect_s3_class(out$created_at, "POSIXct")
    expect_true(is.list(out$segments))
    expect_equal(nrow(out), 1L)
  })
})

test_that("text accessors raise table_missing on schemas without them", {
  with_tables_con("mini", function(con) {
    expect_error(entropia_extractions(con), class = "entropia_error_table_missing")
    expect_error(entropia_transcriptions(con), class = "entropia_error_table_missing")
    expect_error(entropia_layouts(con), class = "entropia_error_table_missing")
  })
})

test_that("text accessors reject a closed connection", {
  con <- withr::with_options(
    list(entropiaR.schema_policy = "allow"),
    entropia_connect(ent_fixture("full"))
  )
  entropia_disconnect(con)
  expect_error(entropia_extractions(con), class = "entropia_error_invalid_connection")
  expect_error(entropia_transcriptions(con), class = "entropia_error_invalid_connection")
  expect_error(entropia_layouts(con), class = "entropia_error_invalid_connection")
})
