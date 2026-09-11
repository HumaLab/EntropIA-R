test_that("report rejects incomplete overview objects", {
  expect_error(entropia_report(list(), tempfile()), class = "entropia_error_invalid_argument")
})

test_that("report redaction strips paths and identifying labels", {
  x <- list(
    counts = tibble::tibble(metric = "items", unit = "item", n = 1L),
    collections = tibble::tibble(
      collection_id = "abc", collection_name = "Secret",
      n_items = 1L, n_assets = 1L, n = 1L
    ),
    temporal = tibble::tibble(date = as.POSIXct("2020-01-01", tz = "UTC"), n = 1L),
    quality = tibble::tibble(
      metric = "m", group_id = "abc", group = "Secret",
      unit = "item", n = 1L, total = 1L, pct = 1, status = "ok"
    ),
    entities = tibble::tibble(
      entity_type = "p", value = "Juan", n = 1L, n_items = 1L, total = 1L, pct = 1
    ),
    topics = tibble::tibble(name = "HUELGA", n = 1L, n_items = 1L, total = 1L, pct = 1),
    provenance = list(source_path = "C:/secret.sqlite"),
    selection = list(collection_ids = "abc", entity_source = "x", model_name = "y")
  )
  r <- entropiaR:::ent_report_redact(x)
  expect_null(r$provenance$source_path)
  expect_true(isTRUE(r$provenance$redacted))
  expect_false(identical(r$collections$collection_name, "Secret"))
  expect_false("Juan" %in% r$entities$value)
  expect_false("HUELGA" %in% r$topics$name)
})

test_that("report renders a frozen HTML dashboard with Quarto", {
  skip_if_not_installed("ggplot2")
  skip_if_not_installed("knitr")
  skip_if_not_installed("rmarkdown")
  if (!nzchar(Sys.which("quarto"))) {
    skip("quarto executable not on PATH")
  }
  # Quarto starts a clean R process that loads the installed package, not
  # pkgload::load_all(), so this render is skipped in development tests.
  skip_if(
    requireNamespace("pkgload", quietly = TRUE) &&
      isTRUE(pkgload::is_dev_package("entropiaR")),
    "Quarto subprocess cannot see load_all() changes"
  )
  con <- ent_connect_fixture("full")
  on.exit(entropia_disconnect(con), add = TRUE)
  eda <- entropia_overview(con)
  dest <- tempfile(fileext = ".html")
  written <- entropia_report(eda, dest)
  expect_true(file.exists(written))
  expect_error(entropia_report(eda, dest), class = "entropia_error_dest_exists")
})
