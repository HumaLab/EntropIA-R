# Visualization helpers (Task 23): thin ggplot2 wrappers on analysis
# summaries.
#
# The three exported functions consume the materialised summaries produced by
# the analysis and quality layers (entropia_temporal_profile(),
# entropia_entity_frequency(), entropia_corpus_quality()) and return a ggplot2
# object. They never render -- the user adds facets, labels and themes with `+`
# and prints or saves the result. ggplot2 lives in Suggests, so every function
# guards with requireNamespace() and errors with
# entropia_error_missing_dependency when it is absent.

# Require ggplot2 (Suggests) with a clear, actionable error. Called first in
# every exported plotting function so a missing dependency fails loudly
# instead of surfacing as a cryptic namespace error mid-plot.
ent_require_ggplot2 <- function() {
  if (!requireNamespace("ggplot2", quietly = TRUE)) {
    ent_abort(
      "entropia_error_missing_dependency",
      c(
        "Plotting requires the {.pkg ggplot2} package.",
        i = "Install it with {.code install.packages(\"ggplot2\")}.",
        i = paste0(
          "The plotting helpers are optional ({.pkg Suggests}); the rest of ",
          "entropiaR works without them."
        )
      )
    )
  }
  invisible(TRUE)
}

# Percent-axis label formatter (base R; avoids a scales dependency).
ent_pct_labels <- function(x) paste0(sprintf("%.0f", x * 100), "%")

# Names of the date-like columns (POSIXct or Date) of a tibble.
ent_date_cols <- function(x) {
  names(x)[vapply(
    x,
    function(col) inherits(col, "POSIXct") || inherits(col, "Date"),
    logical(1)
  )]
}

#' Plot a temporal profile
#'
#' Plots the output of [entropia_temporal_profile()] -- counts per time bucket
#' -- as a line chart. The date column is auto-detected when `x` carries exactly
#' one `POSIXct`/`Date` column (the bucket); pass `date_var` when the profile
#' carries several date-like columns (e.g. grouping columns that are themselves
#' dates).
#'
#' The returned `ggplot` is deliberately bare: add labels, a title, a theme or
#' facets with `+`. A profile built with a `by` grouping draws one line across
#' all groups; add `aes(colour = <group>)` yourself to distinguish them.
#'
#' @param x A data frame or tibble with a `n` count column and a date column,
#'   e.g. the output of [entropia_temporal_profile()].
#' @param date_var Optional date column to plot on the x axis, selected by name
#'   or bare (tidyselect). `NULL` (default) auto-detects the single date column
#'   of `x`.
#' @return A `ggplot` object.
#' @export
#' @examples
#' prof <- data.frame(
#'   created_at = as.POSIXct(c("2026-01-01", "2026-02-01"), tz = "UTC"),
#'   n = c(3L, 5L)
#' )
#' p <- entropia_plot_temporal(prof)
#' if (requireNamespace("ggplot2", quietly = TRUE)) {
#'   p + ggplot2::labs(title = "Items over time")
#' }
entropia_plot_temporal <- function(x, date_var = NULL) {
  ent_require_ggplot2()
  x <- ent_require_tibble(x)
  ent_require_analysis_cols(x, "n", "entropia_plot_temporal")

  date_var <- rlang::enquo(date_var)
  if (rlang::quo_is_null(date_var)) {
    date_cols <- ent_date_cols(x)
    if (length(date_cols) == 0L) {
      ent_abort(
        "entropia_error_invalid_argument",
        c(
          "No date column found on {.arg x}.",
          i = paste0(
            "Pass {.arg date_var} (a {.cls POSIXct} or {.cls Date} column), ",
            "e.g. the bucket column produced by {.fn entropia_temporal_profile}."
          )
        )
      )
    }
    if (length(date_cols) > 1L) {
      ent_abort(
        "entropia_error_invalid_argument",
        c(
          "Several date columns on {.arg x}: {.val {date_cols}}.",
          i = "Pass {.arg date_var} to pick the one to plot."
        )
      )
    }
    date_col <- date_cols
  } else {
    date_col <- ent_select_cols(x, date_var, "date_var", exactly = 1L)
  }

  ggplot2::ggplot(x, ggplot2::aes(
    x = !!rlang::sym(date_col),
    y = !!rlang::sym("n")
  )) +
    ggplot2::geom_line() +
    ggplot2::geom_point() +
    ggplot2::labs(x = date_col, y = "n", title = "Temporal profile")
}

#' Plot entity frequencies
#'
#' Plots the output of [entropia_entity_frequency()] as a horizontal bar chart
#' of the top entity values, filled by a column of `x` (by default
#' `entity_type`). `value` is reordered by count so the most frequent entity
#' sits at the top of the chart (via `coord_flip()`).
#'
#' @param x A data frame or tibble with `value` and `n` columns (and typically
#'   `entity_type`), e.g. the output of [entropia_entity_frequency()].
#' @param top Number of top rows (by `n`) to plot. Default `10`.
#' @param fill Column of `x` to colour the bars by, selected by name or bare.
#'   Default `"entity_type"`.
#' @return A `ggplot` object.
#' @export
#' @examples
#' freq <- data.frame(
#'   entity_type = c("person", "organization", "place"),
#'   value = c("Juan Pérez", "CGT", "Mar del Plata"),
#'   n = c(4L, 3L, 2L)
#' )
#' p <- entropia_plot_entities(freq)
#' if (requireNamespace("ggplot2", quietly = TRUE)) {
#'   p + ggplot2::labs(title = "Custom title")
#' }
entropia_plot_entities <- function(x, top = 10, fill = "entity_type") {
  ent_require_ggplot2()
  x <- ent_require_tibble(x)
  ent_require_analysis_cols(x, c("value", "n"), "entropia_plot_entities")
  fill_col <- ent_select_cols(x, rlang::enquo(fill), "fill", exactly = 1L)
  if (
    !is.numeric(top) || length(top) != 1L || is.na(top) ||
      top < 1 || top != as.integer(top)
  ) {
    ent_abort(
      "entropia_error_invalid_argument",
      "{.arg top} must be a single positive integer (received {.val {top}})."
    )
  }
  top <- as.integer(top)
  if (nrow(x) == 0L) {
    ent_abort(
      "entropia_error_invalid_argument",
      "{.arg x} has no rows to plot."
    )
  }

  # Keep the `top` most frequent values. The frequency summary is ordered
  # deterministically (type, count desc, value), so with_ties = FALSE is stable.
  d <- dplyr::slice_max(x, .data$n, n = top, with_ties = FALSE)
  # Order bars by count ascending so coord_flip() puts the most frequent on top.
  d$value <- stats::reorder(d$value, d$n)

  ggplot2::ggplot(d, ggplot2::aes(
    x = !!rlang::sym("value"),
    y = !!rlang::sym("n"),
    fill = !!rlang::sym(fill_col)
  )) +
    ggplot2::geom_col() +
    ggplot2::coord_flip() +
    ggplot2::labs(x = NULL, y = "n", title = "Top entities")
}

#' Plot corpus coverage
#'
#' Plots the output of [entropia_corpus_quality()] -- coverage proportions per
#' metric and group -- as a bar chart. With a single `metric` the chart is a
#' plain bar chart of the coverage proportion by group; with several metrics the
#' bars are faceted by `metric`, each panel carrying its own groups and y scale.
#'
#' The y axis is labelled as a percentage. `pct` is `NA` for groups with no
#' total (e.g. a metric absent from a corpus); those bars are dropped by
#' `ggplot2` like any `NA` aesthetic.
#'
#' @param x A data frame or tibble with `metric`, `group` and `pct` columns,
#'   e.g. the output of [entropia_corpus_quality()].
#' @param metric Optional character vector of metric(s) to plot, a subset of
#'   `unique(x$metric)`. `NULL` (default) plots all metrics.
#' @return A `ggplot` object.
#' @export
#' @examples
#' q <- data.frame(
#'   metric = c("ocr_coverage", "metadata_coverage"),
#'   group = c("image", "Archivo de prueba"),
#'   n = c(250L, 3L),
#'   total = c(2428L, 3L),
#'   pct = c(250 / 2428, 1)
#' )
#' p <- entropia_plot_coverage(q)
#' if (requireNamespace("ggplot2", quietly = TRUE)) {
#'   p + ggplot2::labs(title = "Coverage")
#' }
entropia_plot_coverage <- function(x, metric = NULL) {
  ent_require_ggplot2()
  x <- ent_require_tibble(x)
  ent_require_analysis_cols(x, c("metric", "group", "pct"), "entropia_plot_coverage")

  if (!is.null(metric)) {
    if (!is.character(metric) || length(metric) == 0L || anyNA(metric)) {
      ent_abort(
        "entropia_error_invalid_argument",
        paste0(
          "{.arg metric} must be {.code NULL} or a character vector of ",
          "metric names."
        )
      )
    }
    unknown <- setdiff(metric, unique(x$metric))
    if (length(unknown) > 0L) {
      ent_abort(
        "entropia_error_invalid_argument",
        c(
          "Unknown metric{?s}: {.val {unknown}}.",
          i = "Metrics available: {.val {unique(x$metric)}}."
        )
      )
    }
    x <- x[x$metric %in% metric, , drop = FALSE]
  }
  if (nrow(x) == 0L) {
    ent_abort(
      "entropia_error_invalid_argument",
      "{.arg x} has no rows to plot."
    )
  }

  p <- ggplot2::ggplot(x, ggplot2::aes(
    x = !!rlang::sym("group"),
    y = !!rlang::sym("pct"),
    fill = !!rlang::sym("group")
  )) +
    ggplot2::geom_col() +
    ggplot2::scale_y_continuous(labels = ent_pct_labels, limits = c(0, NA)) +
    ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 45, hjust = 1)) +
    ggplot2::labs(x = NULL, y = "coverage", title = "Corpus coverage")

  if (length(unique(x$metric)) > 1L) {
    p <- p + ggplot2::facet_wrap("metric")
  }
  p
}
