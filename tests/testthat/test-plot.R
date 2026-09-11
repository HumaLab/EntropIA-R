# Tests for Task 23 (visualization helpers).
#
# entropia_plot_coverage(), entropia_plot_temporal() and
# entropia_plot_entities() are thin ggplot2 helpers on analysis summaries.
# They return ggplot objects (never render), guard ggplot2 behind
# requireNamespace (Suggests), and remain user-extensible with `+`.
# vdiffr snapshots are optional: they run only where vdiffr is installed
# (skip_if_not_installed) so the suite stays green without it.

with_plot_con <- function(name, f) {
  con <- ent_connect_fixture(name)
  on.exit(try(entropia_disconnect(con), silent = TRUE), add = TRUE)
  f(con)
}

# The three summaries the plots consume, built on the full fixture (mirrors
# the test-analysis.R / test-quality.R building blocks).
plot_temporal_summary <- function(con) {
  entropia_temporal_profile(entropia_collect(entropia_items(con)), created_at)
}

plot_entity_summary <- function(con) {
  entropia_entity_frequency(entropia_collect(entropia_entities(con)))
}

plot_coverage_summary <- function(con) {
  entropia_corpus_quality(con)
}

# --- entropia_plot_temporal ----------------------------------------------------

test_that("temporal series with identical labels retain distinct IDs", {
  skip_if_not_installed("ggplot2")
  x <- data.frame(
    date = rep(as.Date(c("2026-01-01", "2026-02-01")), 2),
    collection_id = rep(c(1L, 2L), each = 2), collection_name = "Archivo",
    n = c(1, 2, 10, 20)
  )
  b <- ggplot2::ggplot_build(entropia_plot_temporal(x))$data[[1]]
  expect_equal(sort(vapply(split(b$y, b$group), sum, numeric(1))), c(3, 30), ignore_attr = TRUE)
  expect_equal(sort(as.numeric(table(b$group))), c(2, 2))
  expect_error(entropia_plot_temporal(transform(x, other = "ambiguous")),
    class = "entropia_error_invalid_argument"
  )
})

test_that("temporal plot auto-detects the date column and accepts explicit date_var", {
  skip_if_not_installed("ggplot2")
  df <- data.frame(
    t = as.POSIXct(c("2026-01-01", "2026-02-01"), tz = "UTC"),
    n = c(3L, 5L)
  )
  p1 <- entropia_plot_temporal(df)
  p2 <- entropia_plot_temporal(df, date_var = "t")
  p3 <- entropia_plot_temporal(df, date_var = t)
  for (p in list(p1, p2, p3)) {
    b <- ggplot2::ggplot_build(p)$data[[2]]
    expect_equal(b$y, c(3, 5))
    expect_equal(as.numeric(b$x), as.numeric(df$t))
  }
})

test_that("temporal plot renders and is user-extensible", {
  skip_if_not_installed("ggplot2")
  with_plot_con("full", function(con) {
    p <- entropia_plot_temporal(plot_temporal_summary(con))
    # ggplot_build runs the full data transform; errors on invalid input
    built <- ggplot2::ggplot_build(p)
    expect_equal(sort(built$data[[2]]$y), sort(p$data$n))
    ext <- p + ggplot2::labs(title = "Custom title")
    expect_s3_class(ext, "ggplot")
  })
})

test_that("temporal plot validates input", {
  skip_if_not_installed("ggplot2")
  cls <- "entropia_error_invalid_argument"
  expect_error(entropia_plot_temporal(data.frame(n = 1L)), class = cls)
  # ambiguous: two date columns without date_var
  df2 <- data.frame(
    a = as.POSIXct("2026-01-01", tz = "UTC"),
    b = as.POSIXct("2026-01-02", tz = "UTC"),
    n = 1L
  )
  expect_error(entropia_plot_temporal(df2), class = cls)
  # date_var selecting more than one column
  expect_error(entropia_plot_temporal(df2, date_var = c(a, b)), class = cls)
  # missing n column
  expect_error(
    entropia_plot_temporal(data.frame(t = as.POSIXct("2026-01-01", tz = "UTC"))),
    class = cls
  )
  # not a data.frame / lazy table
  expect_error(entropia_plot_temporal(as.POSIXct("2026-01-01", tz = "UTC")), class = cls)
  with_plot_con("full", function(con) {
    expect_error(entropia_plot_temporal(entropia_items(con)), class = cls)
  })
})

# --- entropia_plot_entities -----------------------------------------------------

test_that("entity bars do not stack identical values across types or IDs", {
  skip_if_not_installed("ggplot2")
  x <- data.frame(
    value = "Roma", entity_type = c("person", "place", "place"),
    collection_id = c(1, 1, 2), collection_name = "Archivo", n = c(3, 7, 11)
  )
  b <- ggplot2::ggplot_build(entropia_plot_entities(x))$data[[1]]
  expect_equal(sort(b$ymax - b$ymin), c(3, 7, 11))
  expect_equal(anyDuplicated(b$x), 0L)
  g <- ggplot2::ggplot_build(entropia_plot_entities(x, top = 1, top_by = "group"))$data[[1]]
  expect_equal(sort(g$y), c(7, 11))
  global <- ggplot2::ggplot_build(entropia_plot_entities(x, top = 1))$data[[1]]
  expect_equal(global$y, 11)
})

test_that("entity plot honours top and reorders bars by count", {
  skip_if_not_installed("ggplot2")
  df <- data.frame(
    entity_type = c("person", "person", "place", "place"),
    value = c("Juan", "Ana", "Madrid", "Roma"),
    n = c(10L, 5L, 2L, 1L)
  )
  p <- entropia_plot_entities(df, top = 2)
  b <- ggplot2::ggplot_build(p)$data[[1]]
  expect_equal(b$y[order(b$x)], c(5, 10))
  expect_equal(b$ymax - b$ymin, b$y)
})

test_that("entity plot accepts a custom fill column", {
  skip_if_not_installed("ggplot2")
  df <- data.frame(
    collection_name = c("A", "A", "B"),
    entity_type = c("person", "person", "person"),
    value = c("Juan", "Ana", "Pedro"),
    n = c(3L, 2L, 1L)
  )
  p <- entropia_plot_entities(df, fill = collection_name)
  p2 <- entropia_plot_entities(df, fill = "collection_name")
  b <- ggplot2::ggplot_build(p)$data[[1]]
  expect_equal(b$fill[1], b$fill[2])
  expect_false(b$fill[1] == b$fill[3])
  expect_equal(b$fill, ggplot2::ggplot_build(p2)$data[[1]]$fill)
})

test_that("entity plot renders and is user-extensible", {
  skip_if_not_installed("ggplot2")
  with_plot_con("full", function(con) {
    p <- entropia_plot_entities(plot_entity_summary(con))
    built <- ggplot2::ggplot_build(p)
    expect_equal(sort(built$data[[1]]$y), sort(p$data$n))
    ext <- p + ggplot2::labs(title = "Custom title")
    expect_s3_class(ext, "ggplot")
  })
})

test_that("entity plot validates input, top and fill", {
  skip_if_not_installed("ggplot2")
  cls <- "entropia_error_invalid_argument"
  df <- data.frame(entity_type = "person", value = "Juan", n = 1L)
  # missing columns (value/n for the function; entity_type for the default fill)
  expect_error(entropia_plot_entities(data.frame(entity_type = "person")), class = cls)
  expect_error(
    entropia_plot_entities(data.frame(value = "Juan", n = 1L)),
    class = cls
  )
  # top validation
  expect_error(entropia_plot_entities(df, top = 0), class = cls)
  expect_error(entropia_plot_entities(df, top = c(1L, 2L)), class = cls)
  expect_error(entropia_plot_entities(df, top = "10"), class = cls)
  expect_error(entropia_plot_entities(df, top = 1.5), class = cls)
  # fill selection
  expect_error(entropia_plot_entities(df, fill = nope), class = cls)
  # Empty summaries have an intentional, renderable annotation.
  p <- entropia_plot_entities(data.frame(
    entity_type = character(), value = character(), n = integer()
  ))
  expect_warning(b <- ggplot2::ggplot_build(p), NA)
  expect_match(b$data[[1]]$label, "Sin datos")
  # not a data.frame / lazy table
  expect_error(entropia_plot_entities(c("a")), class = cls)
  with_plot_con("full", function(con) {
    expect_error(entropia_plot_entities(entropia_entities(con)), class = cls)
  })
})

# --- entropia_plot_coverage -----------------------------------------------------

test_that("coverage preserves IDs and annotates missing denominators", {
  skip_if_not_installed("ggplot2")
  x <- data.frame(
    metric = "text", group = "Archivo", group_id = c(1, 2, 3),
    pct = c(0.2, 0.8, NA_real_), total = c(10, 10, NA),
    status = c("ok", "ok", "no_data")
  )
  expect_warning(b <- ggplot2::ggplot_build(entropia_plot_coverage(x)), NA)
  expect_equal(sort(b$data[[1]]$y), c(0.2, 0.8))
  expect_equal(anyDuplicated(b$data[[1]]$x), 0L)
  expect_match(b$data[[2]]$label, "no_data")
  expect_warning(empty <- ggplot2::ggplot_build(entropia_plot_coverage(x[3, ])), NA)
  expect_match(empty$data[[2]]$label, "Sin valor")
})

test_that("coverage plot with a single metric is unfaceted and filtered", {
  skip_if_not_installed("ggplot2")
  with_plot_con("full", function(con) {
    p <- entropia_plot_coverage(plot_coverage_summary(con), metric = "ocr_coverage")
    expect_true(inherits(p$facet, "FacetNull"))
    expect_true(all(p$data$metric == "ocr_coverage"))
    expect_gt(nrow(p$data), 0L)
  })
})

test_that("coverage plot renders and is user-extensible", {
  skip_if_not_installed("ggplot2")
  with_plot_con("full", function(con) {
    p <- entropia_plot_coverage(plot_coverage_summary(con))
    built <- ggplot2::ggplot_build(p)
    expect_true(all(is.finite(built$data[[1]]$y)))
    ext <- p + ggplot2::labs(title = "Custom title")
    expect_s3_class(ext, "ggplot")
  })
})

test_that("coverage plot validates metric, columns, empty input and input type", {
  skip_if_not_installed("ggplot2")
  cls <- "entropia_error_invalid_argument"
  df <- data.frame(
    metric = c("ocr_coverage", "metadata_coverage"),
    group = c("image", "Archivo"),
    n = c(1L, 2L),
    total = c(2L, 2L),
    pct = c(0.5, 1)
  )
  expect_error(entropia_plot_coverage(df, metric = "bogus"), class = cls)
  expect_error(entropia_plot_coverage(df, metric = c("ocr_coverage", "bogus")), class = cls)
  expect_error(entropia_plot_coverage(df, metric = 1), class = cls)
  expect_error(entropia_plot_coverage(df, metric = character(0)), class = cls)
  # missing columns
  expect_error(entropia_plot_coverage(data.frame(a = 1)), class = cls)
  # Empty input is an annotated plot, not an error.
  expect_warning(b <- ggplot2::ggplot_build(entropia_plot_coverage(df[0, ])), NA)
  expect_match(b$data[[1]]$label, "Sin datos")
  # not a data.frame / lazy table
  expect_error(entropia_plot_coverage(c("a")), class = cls)
  with_plot_con("full", function(con) {
    expect_error(entropia_plot_coverage(entropia_corpus(con)), class = cls)
  })
})

test_that("faceted temporal series never connect different IDs", {
  skip_if_not_installed("ggplot2")
  x <- data.frame(
    date = rep(as.Date(c("2026-01-01", "2026-02-01")), 2),
    group_id = rep(c(1, 2), each = 2), group = "Igual", n = c(1, 2, 10, 20)
  )
  b <- ggplot2::ggplot_build(entropia_plot_temporal(x, group = group, facet = group))$data[[1]]
  expect_equal(sort(vapply(split(b$y, b$PANEL), sum, numeric(1))), c(3, 30), ignore_attr = TRUE)
  expect_error(entropia_plot_temporal(rbind(x, x[1, ]), group = group),
    class = "entropia_error_invalid_argument"
  )
})

test_that("new bar plots preserve repeated names and undefined missingness", {
  skip_if_not_installed("ggplot2")
  collections <- data.frame(collection_id = c(1, 2), collection_name = "Igual", n_items = c(2, 9))
  b <- ggplot2::ggplot_build(entropia_plot_collections(collections))$data[[1]]
  expect_equal(anyDuplicated(b$x), 0L)
  expect_equal(sort(b$y), c(2, 9))
  topics <- data.frame(name = c("Tema", "Tema"), group_id = c(1, 2), n = c(3, 7))
  b <- ggplot2::ggplot_build(entropia_plot_topics(topics))$data[[1]]
  expect_equal(anyDuplicated(b$x), 0L)
  expect_equal(sort(b$ymax - b$ymin), c(3, 7))
  missing <- data.frame(variable = "a", n = 0L, total = 0L, pct = NA_real_, status = "empty")
  expect_warning(b <- ggplot2::ggplot_build(entropia_plot_missing(missing)), NA)
  expect_match(b$data[[2]]$label, "empty")
})

test_that("distributions and scatter annotate unusable measurements without warnings", {
  skip_if_not_installed("ggplot2")
  x <- data.frame(a = c(NA_real_, Inf, -1), b = c(2, 3, NA_real_))
  for (type in c("histogram", "ecdf", "boxplot")) {
    expect_warning(b <- ggplot2::ggplot_build(entropia_plot_distribution(x, a, type = type, log = TRUE)), NA)
    expect_match(b$data[[1]]$label, "Sin observaciones")
  }
  expect_warning(b <- ggplot2::ggplot_build(entropia_plot_scatter(x, a, b)), NA)
  expect_match(b$data[[1]]$label, "Sin pares")
  x <- data.frame(a = c(1, 2, 3, NA), b = c(4, 5, 6, 7))
  b <- ggplot2::ggplot_build(entropia_plot_scatter(x, a, b))$data[[1]]
  expect_equal(b$x, c(1, 2, 3))
  expect_equal(b$y, c(4, 5, 6))
})

test_that("correlations exclude identifiers and handle constants and missing pairs", {
  skip_if_not_installed("ggplot2")
  x <- data.frame(
    id = 1:3, item_id = 3:1, a = 1:3, b = 2:4,
    constant = 1, absent = NA_real_, date = as.Date("2026-01-01") + 0:2
  )
  expect_warning(p <- entropia_plot_correlation(x, c(id, item_id, a, b, constant, absent, date)), NA)
  expect_warning(b <- ggplot2::ggplot_build(p), NA)
  expect_setequal(p$data$variable_x, c("a", "b", "constant", "absent"))
  expect_equal(p$data$correlation[p$data$variable_x == "a" & p$data$variable_y == "b"], 1)
  expect_true(all(is.na(p$data$correlation[p$data$variable_x == "constant"])))
  expect_true(any(grepl("Sin datos", b$data[[2]]$label)))
})

# --- vdiffr snapshots (optional: run where vdiffr is installed) -----------------

test_that("plot snapshots are stable", {
  skip_on_cran()
  skip_on_ci()
  skip_if_not_installed("ggplot2")
  skip_if_not_installed("vdiffr")
  with_plot_con("full", function(con) {
    vdiffr::expect_doppelganger(
      "entropia-plot-coverage-full",
      entropia_plot_coverage(plot_coverage_summary(con))
    )
    vdiffr::expect_doppelganger(
      "entropia-plot-temporal-full",
      entropia_plot_temporal(plot_temporal_summary(con))
    )
    vdiffr::expect_doppelganger(
      "entropia-plot-entities-full",
      entropia_plot_entities(plot_entity_summary(con))
    )
  })
})
