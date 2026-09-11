test_that("dashboard requires a SQLite snapshot and does not start a server", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("bslib")
  skip_if_not_installed("ggplot2")
  expect_error(
    entropia_dashboard(tempfile()),
    class = "entropia_error_not_sqlite"
  )
  path <- ent_fixture("full")
  app <- entropia_dashboard(path)
  expect_s3_class(app, "shiny.appobj")
  expect_true(is.function(app$serverFunc))
})

test_that("dashboard rejects a nonempty WAL instead of opening a live file", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("bslib")
  skip_if_not_installed("ggplot2")
  path <- ent_fixture("full")
  writeBin(as.raw(1:8), paste0(path, "-wal"))
  expect_error(entropia_dashboard(path), class = "entropia_error_invalid_argument")
})
