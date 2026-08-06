# Tests for Task 22 (reproducibility layer).
#
# entropia_analysis_dataset() assembles the lazy corpus, applies filter
# expressions, and materialises a deterministically ordered tibble of class
# entropia_dataset carrying an entropia_prov provenance attribute.
# entropia_provenance() / entropia_write_provenance() read the stamp and
# persist it as a JSON sidecar. Fixture-based: the full fixture corpus has 5
# assets (3 pdf incl. pages, 1 image, 1 audio).

with_dataset_con <- function(name, f) {
  con <- ent_connect_fixture(name)
  on.exit(try(entropia_disconnect(con), silent = TRUE), add = TRUE)
  f(con)
}

DS_ERR <- "entropia_error_invalid_argument"

# --- entropia_analysis_dataset: shape and provenance fields --------------------

test_that("analysis dataset is a typed tibble with correct provenance fields", {
  with_dataset_con("full", function(con) {
    ds <- entropia_analysis_dataset(con, asset_type == "image", name = "imagenes")
    expect_s3_class(ds, "entropia_dataset")
    expect_s3_class(ds, "tbl_df")
    expect_equal(nrow(ds), 1L)
    expect_true(all(ds$asset_type == "image"))

    prov <- entropia_provenance(ds)
    expect_s3_class(prov, "entropia_provenance")
    expect_identical(prov$name, "imagenes")
    expect_identical(prov$schema_version, "0029_rag_chunks")
    expect_identical(prov$content_hash, attr(con, "content_hash"))
    expect_identical(prov$source_path, attr(con, "path"))
    expect_identical(prov$filters, "asset_type == \"image\"")
    expect_identical(prov$package_version, as.character(utils::packageVersion("entropiaR")))
    expect_match(prov$built_at, "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}")
    # R devel reports "R Under development (unstable) ..." instead of
    # "R version X.Y.Z ..."; accept both formats.
    expect_match(prov$r_version, "^(R version|R Under development)")
  })
})

test_that("analysis dataset without filters builds the whole corpus, unnamed", {
  with_dataset_con("full", function(con) {
    ds <- entropia_analysis_dataset(con)
    expect_equal(nrow(ds), 5L)
    expect_identical(ds$asset_id, sort(ds$asset_id)) # deterministic ordering
    prov <- entropia_provenance(ds)
    expect_null(prov$name)
    expect_identical(prov$filters, character(0))
  })
})

test_that("analysis dataset supports multiple filters applied in SQL", {
  with_dataset_con("full", function(con) {
    # PDF pages carry a non-NULL parent_asset_id; keep only the pdf parent.
    ds <- entropia_analysis_dataset(con, asset_type == "pdf", is.na(parent_asset_id))
    expect_true(all(ds$asset_type == "pdf"))
    expect_true(all(is.na(ds$parent_asset_id)))
    expect_equal(nrow(ds), 1L)
  })
})

# --- reproducibility: identical inputs -> identical datasets --------------------

test_that("building the same dataset twice yields identical data and stable provenance", {
  # Open two independent copies of the same fixture so the content hash is
  # computed independently on each connection — if ent_content_hash() were
  # non-deterministic or data-dependent the hashes would differ.
  con1 <- ent_connect_fixture("full")
  on.exit(try(entropia_disconnect(con1), silent = TRUE), add = TRUE)
  con2 <- ent_connect_fixture("full")
  on.exit(try(entropia_disconnect(con2), silent = TRUE), add = TRUE)

  ds1 <- entropia_analysis_dataset(con1, asset_type == "image", name = "img")
  ds2 <- entropia_analysis_dataset(con2, asset_type == "image", name = "img")
  # byte-identical rows (deterministic arrange on asset_id); the entropia_prov
  # attribute differs only in built_at, so compare the data alone
  expect_equal(as.data.frame(ds1), as.data.frame(ds2), ignore_attr = "entropia_prov")
  p1 <- entropia_provenance(ds1)
  p2 <- entropia_provenance(ds2)
  # stable fields identical across independent connections; only the build
  # timestamp and source (temp) path differ
  expect_identical(p1$schema_version, p2$schema_version)
  expect_identical(p1$content_hash, p2$content_hash)
  expect_identical(p1$filters, p2$filters)
  expect_identical(p1$package_version, p2$package_version)
  expect_identical(p1$r_version, p2$r_version)
})

# --- entropia_provenance --------------------------------------------------------

test_that("entropia_provenance errors on objects without a stamp", {
  expect_error(entropia_provenance(tibble::tibble(a = 1)), class = DS_ERR)
  expect_error(entropia_provenance(list(x = 1)), class = DS_ERR)
})

# --- entropia_write_provenance: JSON round-trip ---------------------------------

test_that("write provenance round-trips through JSON", {
  with_dataset_con("full", function(con) {
    ds <- entropia_analysis_dataset(con, asset_type == "image", name = "img")
    path <- tempfile(fileext = ".json")
    expect_invisible(entropia_write_provenance(ds, path))
    expect_true(file.exists(path))

    rt <- jsonlite::fromJSON(path)
    expect_identical(unclass(entropia_provenance(ds)), rt)
  })
})

test_that("write provenance validates path and requires a stamp", {
  with_dataset_con("full", function(con) {
    ds <- entropia_analysis_dataset(con)
    expect_error(entropia_write_provenance(ds, c("a", "b")), class = DS_ERR)
    expect_error(entropia_write_provenance(tibble::tibble(a = 1), tempfile()), class = DS_ERR)
  })
})

# --- dataset class methods ------------------------------------------------------

test_that("entropia_dataset print shows the name and schema", {
  with_dataset_con("full", function(con) {
    ds <- entropia_analysis_dataset(con, name = "corpus")
    expect_output(print(ds), "entropia_dataset: corpus")
    expect_output(print(ds), "schema: 0029_rag_chunks")
    expect_output(print(ds), "asset_id")
  })
})

test_that("entropia_dataset glimpse shows the header and columns", {
  with_dataset_con("full", function(con) {
    ds <- entropia_analysis_dataset(con, name = "corpus")
    expect_output(dplyr::glimpse(ds), "entropia_dataset: corpus")
    expect_output(dplyr::glimpse(ds), "asset_id")
  })
})

test_that("as_tibble strips the dataset class and provenance", {
  with_dataset_con("full", function(con) {
    ds <- entropia_analysis_dataset(con)
    plain <- tibble::as_tibble(ds)
    expect_s3_class(plain, "tbl_df")
    expect_false(inherits(plain, "entropia_dataset"))
    expect_null(attr(plain, "entropia_prov"))
    expect_identical(names(plain), names(ds))
    expect_equal(nrow(plain), nrow(ds))
  })
})

# --- validation -----------------------------------------------------------------

test_that("analysis dataset validates name, filters and connection", {
  with_dataset_con("full", function(con) {
    expect_error(entropia_analysis_dataset(con, name = c("a", "b")), class = DS_ERR)
    expect_error(entropia_analysis_dataset(con, name = NA_character_), class = DS_ERR)
    expect_error(entropia_analysis_dataset(con, img = asset_type == "image"), class = DS_ERR)
    # a filter on a column the corpus does not have errors when collected
    expect_error(entropia_analysis_dataset(con, nope == 1))
  })
  con <- ent_connect_fixture("full")
  entropia_disconnect(con)
  expect_error(entropia_analysis_dataset(con), class = "entropia_error_invalid_connection")
})
