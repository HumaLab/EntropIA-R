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

test_that("temporal plot is a ggplot with the expected mapping", {
  skip_if_not_installed("ggplot2")
  with_plot_con("full", function(con) {
    p <- entropia_plot_temporal(plot_temporal_summary(con))
    expect_s3_class(p, "ggplot")
    expect_identical(rlang::as_label(p$mapping$x), "created_at")
    expect_identical(rlang::as_label(p$mapping$y), "n")
  })
})

test_that("temporal plot auto-detects the date column and accepts explicit date_var", {
  skip_if_not_installed("ggplot2")
  df <- data.frame(
    t = as.POSIXct(c("2026-01-01", "2026-02-01"), tz = "UTC"),
    n = c(3L, 5L)
  )
  p1 <- entropia_plot_temporal(df)
  expect_identical(rlang::as_label(p1$mapping$x), "t")
  p2 <- entropia_plot_temporal(df, date_var = "t")
  expect_identical(rlang::as_label(p2$mapping$x), "t")
  p3 <- entropia_plot_temporal(df, date_var = t)
  expect_identical(rlang::as_label(p3$mapping$x), "t")
})

test_that("temporal plot renders and is user-extensible", {
  skip_if_not_installed("ggplot2")
  with_plot_con("full", function(con) {
    p <- entropia_plot_temporal(plot_temporal_summary(con))
    # ggplot_build runs the full data transform; errors on invalid input
    built <- ggplot2::ggplot_build(p)
    expect_true(length(built$data) >= 1L)
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

test_that("entity plot is a ggplot with value/n/fill mapping", {
  skip_if_not_installed("ggplot2")
  with_plot_con("full", function(con) {
    p <- entropia_plot_entities(plot_entity_summary(con))
    expect_s3_class(p, "ggplot")
    expect_identical(rlang::as_label(p$mapping$x), "value")
    expect_identical(rlang::as_label(p$mapping$y), "n")
    expect_identical(rlang::as_label(p$mapping$fill), "entity_type")
  })
})

test_that("entity plot honours top and reorders bars by count", {
  skip_if_not_installed("ggplot2")
  df <- data.frame(
    entity_type = c("person", "person", "place", "place"),
    value = c("Juan", "Ana", "Madrid", "Roma"),
    n = c(10L, 5L, 2L, 1L)
  )
  p <- entropia_plot_entities(df, top = 2)
  # only the two most frequent rows remain in the plot data
  expect_equal(nrow(p$data), 2L)
  expect_identical(sort(p$data$n, decreasing = TRUE), c(10L, 5L))
  # value is a factor reordered by count ascending so coord_flip() puts the
  # most frequent entity on top
  expect_s3_class(p$data$value, "factor")
  expect_identical(levels(p$data$value), c("Ana", "Juan"))
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
  expect_identical(rlang::as_label(p$mapping$fill), "collection_name")
  p2 <- entropia_plot_entities(df, fill = "collection_name")
  expect_identical(rlang::as_label(p2$mapping$fill), "collection_name")
})

test_that("entity plot renders and is user-extensible", {
  skip_if_not_installed("ggplot2")
  with_plot_con("full", function(con) {
    p <- entropia_plot_entities(plot_entity_summary(con))
    built <- ggplot2::ggplot_build(p)
    expect_true(length(built$data) >= 1L)
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
  # empty input
  expect_error(
    entropia_plot_entities(data.frame(
      entity_type = character(), value = character(), n = integer()
    )),
    class = cls
  )
  # not a data.frame / lazy table
  expect_error(entropia_plot_entities(c("a")), class = cls)
  with_plot_con("full", function(con) {
    expect_error(entropia_plot_entities(entropia_entities(con)), class = cls)
  })
})

# --- entropia_plot_coverage -----------------------------------------------------

test_that("coverage plot is a ggplot with group/pct mapping, faceted by metric", {
  skip_if_not_installed("ggplot2")
  with_plot_con("full", function(con) {
    p <- entropia_plot_coverage(plot_coverage_summary(con))
    expect_s3_class(p, "ggplot")
    expect_identical(rlang::as_label(p$mapping$x), "group")
    expect_identical(rlang::as_label(p$mapping$y), "pct")
    expect_identical(rlang::as_label(p$mapping$fill), "group")
    # the full report carries several metrics -> facets
    expect_true(inherits(p$facet, "FacetWrap"))
  })
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
    expect_true(length(built$data) >= 1L)
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
  # empty input
  expect_error(entropia_plot_coverage(df[0, ]), class = cls)
  # not a data.frame / lazy table
  expect_error(entropia_plot_coverage(c("a")), class = cls)
  with_plot_con("full", function(con) {
    expect_error(entropia_plot_coverage(entropia_corpus(con)), class = cls)
  })
})

# --- vdiffr snapshots (optional: run where vdiffr is installed) -----------------

test_that("plot snapshots are stable", {
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
