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

ent_plot_error <- function(message) {
  ent_abort("entropia_error_invalid_argument", message)
}

ent_plot_data <- function(x, cols = character()) {
  ent_require_ggplot2()
  x <- ent_require_tibble(x)
  ent_require_analysis_cols(x, cols, "plot")
  x
}

ent_plot_col <- function(x, q, arg) {
  if (rlang::quo_is_null(q)) {
    return(NULL)
  }
  ent_select_cols(x, q, arg, exactly = 1L)
}

ent_plot_numeric <- function(x, col) {
  ent_require_analysis_cols(x, col, "plot")
  if (length(col) != 1L || !is.numeric(x[[col]]) ||
    inherits(x[[col]], c("Date", "POSIXt", "difftime"))) {
    ent_plot_error("Select a single numeric measurement column.")
  }
  invisible(col)
}

ent_plot_choice <- function(x, choices, arg) {
  if (!is.character(x) || length(x) != 1L || is.na(x) || !x %in% choices) {
    ent_plot_error(paste0(arg, " must be one of: ", paste(choices, collapse = ", "), "."))
  }
  x
}

ent_plot_empty <- function(title, message = "Sin datos para esta selecci\u00f3n") {
  ggplot2::ggplot(data.frame(x = 0, y = 0), ggplot2::aes(x = .data$x, y = .data$y)) +
    ggplot2::geom_text(label = message) +
    ggplot2::theme_void() +
    ggplot2::labs(title = title)
}

ent_plot_note <- function(p, n) {
  if (n > 0L) {
    p <- p + ggplot2::labs(caption = paste(
      n,
      "observaciones sin valor v\u00e1lido; no representadas"
    ))
  }
  p
}

# Prefer IDs to display labels, including when the caller selects a label.
ent_plot_identity <- function(x, col) {
  if (is.null(col)) {
    return(NULL)
  }
  id <- if (identical(col, "group")) "group_id" else sub("_name$", "_id", col)
  if (!identical(id, col) && id %in% names(x)) id else col
}

ent_plot_group <- function(x, group, exclude = character()) {
  if (!is.null(group)) {
    return(ent_plot_identity(x, group))
  }
  metrics <- c("n", "n_items", "n_assets", "total", "pct", "count", "status", "unit")
  candidates <- setdiff(names(x), c(exclude, metrics))
  candidates <- unique(vapply(candidates, function(z) ent_plot_identity(x, z), character(1)))
  if (length(candidates) > 1L) {
    ent_plot_error(paste0(
      "Ambiguous grouping columns: ", paste(candidates, collapse = ", "),
      ". Select group explicitly (and optionally facet)."
    ))
  }
  if (length(candidates)) candidates else NULL
}

ent_plot_key <- function(x, cols) {
  if (!length(cols)) {
    return(rep.int(1L, nrow(x)))
  }
  dplyr::group_indices(dplyr::group_by(x, dplyr::across(dplyr::all_of(unique(cols)))))
}

ent_plot_facets <- function(p, facet) {
  if (!is.null(facet)) {
    p <- p + ggplot2::facet_wrap(ggplot2::vars(!!rlang::sym(facet)),
      scales = "free_x"
    )
  }
  p
}

# A separate position per source row prevents stacking unrelated IDs or labels.
ent_plot_bars <- function(x, label, value, title, fill = NULL, facet = NULL) {
  if (!nrow(x)) {
    return(ent_plot_empty(title))
  }
  ent_plot_numeric(x, value)
  x$.ent_label <- as.character(x[[label]])
  x$.ent_label[is.na(x$.ent_label)] <- "Sin etiqueta"
  x$.ent_bar <- factor(seq_len(nrow(x)), levels = order(x[[value]], na.last = TRUE))
  ok <- is.finite(x[[value]])
  p <- ggplot2::ggplot(x, ggplot2::aes(x = .data$.ent_bar, y = !!rlang::sym(value)))
  if (!is.null(fill)) p <- p + ggplot2::aes(fill = factor(!!rlang::sym(fill)))
  p <- p + ggplot2::geom_col(data = x[ok, , drop = FALSE]) +
    ggplot2::scale_x_discrete(
      labels = stats::setNames(x$.ent_label, as.character(x$.ent_bar)),
      drop = FALSE
    ) +
    ggplot2::coord_flip() + ggplot2::labs(x = NULL, y = value, title = title, fill = fill)
  if (any(!ok)) {
    bad <- x[!ok, , drop = FALSE]
    bad$.ent_status <- "Sin denominador / sin datos"
    if ("status" %in% names(bad)) {
      known <- !is.na(bad$status) & nzchar(as.character(bad$status))
      bad$.ent_status[known] <- paste0("Sin valor (", bad$status[known], ")")
    }
    p <- p + ggplot2::geom_text(
      data = bad,
      ggplot2::aes(x = .data$.ent_bar, y = 0, label = .data$.ent_status),
      inherit.aes = FALSE, hjust = 0
    )
  }
  ent_plot_facets(p, facet)
}

ent_plot_top <- function(x, top, value, group, facet, top_by) {
  if (!is.numeric(top) || length(top) != 1L || !is.finite(top) ||
    top < 1 || top > .Machine$integer.max || top != floor(top)) {
    ent_plot_error("top must be a single positive integer.")
  }
  ent_plot_choice(top_by, c("global", "group"), "top_by")
  ent_plot_numeric(x, value)
  if (identical(top_by, "group") && is.null(group) && is.null(facet)) {
    ent_plot_error("top_by = 'group' requires a group or facet column.")
  }
  keys <- if (top_by == "group") ent_plot_key(x, c(group, facet)) else rep.int(1L, nrow(x))
  # Stable ties follow source order; undefined values rank last.
  rank_value <- x[[value]]
  rank_value[!is.finite(rank_value)] <- NA_real_
  idx <- unlist(lapply(split(seq_len(nrow(x)), keys), function(i) {
    utils::head(i[order(-rank_value[i], i, na.last = TRUE)], as.integer(top))
  }), use.names = FALSE)
  x[idx, , drop = FALSE]
}

#' Plot topic frequencies
#'
#' Rows remain separate, including repeated topic names in different groups.
#' The largest `top` rows are selected globally; ties follow input order.
#' @param x Materialised topic summary with `name` and a numeric value column.
#' @param top Positive integer number of rows to display.
#' @param group Optional grouping column, bare or named. IDs take precedence
#'   over corresponding display names. Ambiguous automatic grouping errors.
#' @param value Numeric column, bare or named; defaults to `n`.
#' @return An extendible `ggplot` object. No database queries are performed.
#' @export
entropia_plot_topics <- function(x, top = 10, group = NULL, value = "n") {
  x <- ent_plot_data(x, "name")
  value <- ent_plot_col(x, rlang::enquo(value), "value")
  group <- ent_plot_group(x, ent_plot_col(x, rlang::enquo(group), "group"), c("name", value))
  x <- ent_plot_top(x, top, value, group, NULL, "global")
  ent_plot_bars(x, "name", value, "Temas principales", fill = group)
}

#' Plot a numeric distribution
#'
#' Non-finite observations are excluded with an explicit caption. Logarithmic
#' plots also exclude nonpositive observations. Histograms overlay groups
#' transparently rather than stacking their counts.
#' @param x A materialised data frame.
#' @param var Numeric measurement column, bare or named.
#' @param by Optional grouping column, bare or named.
#' @param type One of `histogram`, `ecdf`, or `boxplot`.
#' @param bins Positive integer number of histogram bins.
#' @param log Whether to use a base-10 logarithmic measurement axis.
#' @return An extendible `ggplot` object.
#' @export
entropia_plot_distribution <- function(
  x, var, by = NULL, type = "histogram", bins = 30,
  log = FALSE
) {
  x <- ent_plot_data(x)
  var <- ent_plot_col(x, rlang::enquo(var), "var")
  by <- ent_plot_identity(x, ent_plot_col(x, rlang::enquo(by), "by"))
  ent_plot_numeric(x, var)
  ent_plot_choice(type, c("histogram", "ecdf", "boxplot"), "type")
  if (!is.logical(log) || length(log) != 1L || is.na(log)) {
    ent_plot_error("log must be TRUE or FALSE.")
  }
  if (!is.numeric(bins) || length(bins) != 1L || !is.finite(bins) ||
    bins < 1 || bins > .Machine$integer.max || bins != floor(bins)) {
    ent_plot_error("bins must be a positive integer.")
  }
  ok <- is.finite(x[[var]]) & (!log | x[[var]] > 0)
  omitted <- sum(!ok)
  x <- x[ok, , drop = FALSE]
  if (!nrow(x)) {
    return(ent_plot_empty(
      "Distribuci\u00f3n",
      "Sin observaciones v\u00e1lidas para esta escala"
    ))
  }
  if (type == "boxplot") {
    x$.ent_group <- if (is.null(by)) factor("Todas") else factor(x[[by]], exclude = NULL)
    p <- ggplot2::ggplot(x, ggplot2::aes(x = .data$.ent_group, y = !!rlang::sym(var))) +
      ggplot2::geom_boxplot() +
      ggplot2::labs(x = by, y = var)
    if (log) p <- p + ggplot2::scale_y_log10()
  } else {
    p <- ggplot2::ggplot(x, ggplot2::aes(x = !!rlang::sym(var)))
    if (!is.null(by)) {
      p <- p + ggplot2::aes(
        colour = factor(!!rlang::sym(by)),
        fill = factor(!!rlang::sym(by))
      )
    }
    if (type == "histogram") {
      p <- p + ggplot2::geom_histogram(
        bins = as.integer(bins), position = "identity",
        alpha = 0.5
      ) + ggplot2::labs(y = "Frecuencia")
    } else {
      p <- p + ggplot2::stat_ecdf(geom = "step", pad = FALSE) +
        ggplot2::labs(y = "Proporci\u00f3n acumulada")
    }
    if (log) p <- p + ggplot2::scale_x_log10()
  }
  ent_plot_note(p + ggplot2::labs(title = "Distribuci\u00f3n", colour = by, fill = by), omitted)
}

#' Plot missing-value proportions
#'
#' Every variable/group row receives a separate bar. Undefined proportions are
#' annotated rather than represented as zero.
#' @param x The materialised `missing` tibble returned by [entropia_profile()].
#' @return An extendible `ggplot` object.
#' @export
entropia_plot_missing <- function(x) {
  x <- ent_plot_data(x, c("variable", "pct"))
  groups <- setdiff(names(x), c("variable", "n", "total", "pct", "status", "unit"))
  x$.ent_display <- as.character(x$variable)
  for (g in groups) x$.ent_display <- paste(x$.ent_display, x[[g]], sep = " \u00b7 ")
  ent_plot_bars(x, ".ent_display", "pct", "Valores ausentes") +
    ggplot2::scale_y_continuous(labels = ent_pct_labels) +
    ggplot2::labs(y = "Proporci\u00f3n ausente")
}

#' Plot collection counts
#'
#' Collection IDs are shown alongside names so identical names never merge.
#' @param x Materialised collection summary with `collection_id` and
#'   `collection_name` columns.
#' @param value Numeric column, bare or named; defaults to `n_items`.
#' @return An extendible `ggplot` object.
#' @export
entropia_plot_collections <- function(x, value = "n_items") {
  x <- ent_plot_data(x, c("collection_id", "collection_name"))
  value <- ent_plot_col(x, rlang::enquo(value), "value")
  ent_plot_numeric(x, value)
  x$.ent_display <- paste0(x$collection_name, " [", x$collection_id, "]")
  ent_plot_bars(x, ".ent_display", value, "Colecciones")
}

#' Plot two numeric measurements
#' @param x A materialised data frame.
#' @param x_var,y_var Numeric measurement columns, bare or named.
#' @param by Optional grouping column, bare or named.
#' @return An extendible `ggplot` object. Non-finite pairs are explicitly counted
#'   in the caption; an empty selection produces an annotation.
#' @export
entropia_plot_scatter <- function(x, x_var, y_var, by = NULL) {
  x <- ent_plot_data(x)
  xc <- ent_plot_col(x, rlang::enquo(x_var), "x_var")
  yc <- ent_plot_col(x, rlang::enquo(y_var), "y_var")
  by <- ent_plot_identity(x, ent_plot_col(x, rlang::enquo(by), "by"))
  ent_plot_numeric(x, xc)
  ent_plot_numeric(x, yc)
  ok <- is.finite(x[[xc]]) & is.finite(x[[yc]])
  omitted <- sum(!ok)
  x <- x[ok, , drop = FALSE]
  if (!nrow(x)) {
    return(ent_plot_empty("Dispersi\u00f3n", "Sin pares de valores v\u00e1lidos"))
  }
  p <- ggplot2::ggplot(x, ggplot2::aes(x = !!rlang::sym(xc), y = !!rlang::sym(yc)))
  if (!is.null(by)) p <- p + ggplot2::aes(colour = factor(!!rlang::sym(by)))
  ent_plot_note(
    p + ggplot2::geom_point() + ggplot2::labs(title = "Dispersi\u00f3n", colour = by),
    omitted
  )
}

#' Plot correlations of selected numeric measurements
#'
#' Uses pairwise complete finite observations and Pearson correlation. Columns
#' named `id` or ending in `_id` (case insensitive), dates and nonnumeric columns
#' are excluded. Constant columns and pairs with fewer than two observations
#' are annotated as undefined, not replaced by zero.
#' @param x A materialised data frame.
#' @param columns Explicit tidyselect selection of candidate measurements.
#' @return An extendible `ggplot` object.
#' @export
entropia_plot_correlation <- function(x, columns) {
  x <- ent_plot_data(x)
  cols <- ent_select_cols(x, rlang::enquo(columns), "columns")
  cols <- cols[!grepl("(^id$|_id$)", cols, ignore.case = TRUE)]
  cols <- cols[vapply(x[cols], function(z) {
    is.numeric(z) && !inherits(z, c(
      "Date", "POSIXt",
      "difftime"
    ))
  }, logical(1))]
  if (length(cols) < 2L || !nrow(x)) {
    return(ent_plot_empty(
      "Correlaciones",
      "Se necesitan dos mediciones num\u00e9ricas y observaciones"
    ))
  }
  d <- expand.grid(variable_x = cols, variable_y = cols, stringsAsFactors = FALSE)
  d$correlation <- vapply(seq_len(nrow(d)), function(i) {
    a <- x[[d$variable_x[i]]]
    b <- x[[d$variable_y[i]]]
    ok <- is.finite(a) & is.finite(b)
    a <- a[ok]
    b <- b[ok]
    if (length(a) < 2L || length(unique(a)) < 2L || length(unique(b)) < 2L) {
      return(NA_real_)
    }
    stats::cor(a, b)
  }, numeric(1))
  d$label <- ifelse(is.finite(d$correlation), sprintf("%.2f", d$correlation),
    "Sin datos\no constante"
  )
  ggplot2::ggplot(d, ggplot2::aes(
    x = .data$variable_x, y = .data$variable_y,
    fill = .data$correlation
  )) +
    ggplot2::geom_tile() +
    ggplot2::geom_text(ggplot2::aes(label = .data$label)) +
    ggplot2::scale_fill_gradient2(limits = c(-1, 1), na.value = "grey90") +
    ggplot2::labs(x = NULL, y = NULL, fill = "Correlaci\u00f3n", title = "Correlaciones (Pearson)")
}

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
#' facets with `+`. Grouped summaries draw separate lines, preferring IDs to
#' display names. Automatic grouping requires a single unambiguous remaining
#' dimension; otherwise select `group` explicitly. Duplicate dates within a
#' series are rejected rather than joined or aggregated silently.
#'
#' @param group Optional grouping column, bare or named.
#' @param facet Optional faceting column, bare or named.
#' @param value Numeric measure column, bare or named; defaults to `n`.
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
#' if (requireNamespace("ggplot2", quietly = TRUE)) {
#'   p <- entropia_plot_temporal(prof)
#'   p + ggplot2::labs(title = "Elementos a lo largo del tiempo")
#' }
entropia_plot_temporal <- function(x, date_var = NULL, group = NULL, facet = NULL, value = "n") {
  x <- ent_plot_data(x)
  date_col <- ent_plot_col(x, rlang::enquo(date_var), "date_var")
  if (is.null(date_col)) {
    date_col <- ent_date_cols(x)
    if (length(date_col) != 1L) {
      ent_plot_error(paste(
        "Select date_var explicitly: exactly one Date or POSIXct",
        "column is required."
      ))
    }
  }
  if (!date_col %in% ent_date_cols(x)) {
    ent_plot_error("date_var must select a Date or POSIXct column.")
  }
  value <- ent_plot_col(x, rlang::enquo(value), "value")
  ent_plot_numeric(x, value)
  facet <- ent_plot_identity(x, ent_plot_col(x, rlang::enquo(facet), "facet"))
  group <- ent_plot_group(x, ent_plot_col(x, rlang::enquo(group), "group"), c(
    date_col, value,
    facet
  ))
  ok <- is.finite(as.numeric(x[[date_col]])) & is.finite(x[[value]])
  omitted <- sum(!ok)
  x <- x[ok, , drop = FALSE]
  if (!nrow(x)) {
    return(ent_plot_empty(
      "Evoluci\u00f3n temporal",
      "Sin fechas y valores v\u00e1lidos"
    ))
  }
  keys <- unique(c(date_col, group, facet))
  if (anyDuplicated(x[, keys, drop = FALSE])) {
    ent_plot_error(paste(
      "Multiple rows share a date and series. Select group/facet to",
      "distinguish them, or aggregate explicitly before plotting."
    ))
  }
  x$.ent_series <- ent_plot_key(x, c(group, facet))
  # Only draw lines for series with at least two observations.
  size <- tabulate(x$.ent_series)
  lines <- x[size[x$.ent_series] > 1L, , drop = FALSE]
  p <- ggplot2::ggplot(x, ggplot2::aes(
    x = !!rlang::sym(date_col),
    y = !!rlang::sym(value), group = .data$.ent_series
  ))
  if (!is.null(group)) p <- p + ggplot2::aes(colour = factor(!!rlang::sym(group)))
  p <- p + ggplot2::geom_line(data = lines) + ggplot2::geom_point() +
    ggplot2::labs(x = "Fecha", y = value, colour = group, title = "Evoluci\u00f3n temporal")
  ent_plot_note(ent_plot_facets(p, facet), omitted)
}

#' Plot entity frequencies
#'
#' Plots the output of [entropia_entity_frequency()] as a horizontal bar chart
#' of the top entity values, filled by a column of `x` (by default
#' `entity_type`). Each source row has its own bar position, so repeated labels
#' or distinct IDs are never stacked or silently merged. Highest values appear
#' at the top. Global ranking selects rows, not aggregated labels; group ranking
#' selects up to `top` rows per group/facet combination. Ties use input order.
#'
#' @param group Optional grouping column, bare or named. Automatic grouping
#'   errors if remaining dimensions are ambiguous; IDs take precedence.
#' @param facet Optional faceting column, bare or named.
#' @param top_by Either `global` (default) or `group`.
#' @param value Numeric measure column, bare or named; defaults to `n`.
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
#'   value = c("Juan P<U+00E9>rez", "CGT", "Mar del Plata"),
#'   n = c(4L, 3L, 2L)
#' )
#' if (requireNamespace("ggplot2", quietly = TRUE)) {
#'   p <- entropia_plot_entities(freq)
#'   p + ggplot2::labs(title = "Entidades destacadas")
#' }
entropia_plot_entities <- function(
  x, top = 10, fill = "entity_type", group = NULL, facet = NULL,
  top_by = "global", value = "n"
) {
  x <- ent_plot_data(x, "value")
  if (nrow(x) == 0L) {
    return(ent_plot_empty("Entidades principales"))
  }
  fill <- ent_plot_identity(x, ent_plot_col(x, rlang::enquo(fill), "fill"))
  value <- ent_plot_col(x, rlang::enquo(value), "value")
  facet <- ent_plot_identity(x, ent_plot_col(x, rlang::enquo(facet), "facet"))
  group <- ent_plot_group(
    x, ent_plot_col(x, rlang::enquo(group), "group"),
    c("value", "entity_type", value, fill, facet)
  )
  x <- ent_plot_top(x, top, value, group, facet, top_by)
  x$.ent_display <- as.character(x$value)
  for (col in unique(c("entity_type"["entity_type" %in% names(x)], group, fill))) {
    x$.ent_display <- paste0(x$.ent_display, " [", x[[col]], "]")
  }
  ent_plot_bars(x, ".ent_display", value, "Entidades principales", fill, facet)
}

#' Plot corpus coverage
#'
#' Plots the output of [entropia_corpus_quality()] -- coverage proportions per
#' metric and group -- as a bar chart. With a single `metric` the chart is a
#' plain bar chart of the coverage proportion by group; with several metrics the
#' bars are faceted by `metric`, each panel carrying its own groups and y scale.
#'
#' The y axis is labelled as a percentage. `pct` is `NA` for groups with no
#' total (e.g. a metric absent from a corpus); these rows receive an explicit
#' annotation, using `status` when available, instead of a misleading zero bar.
#' Optional `group_id` is displayed alongside the label; distinct IDs never
#' merge. Empty selections produce a Spanish no-data annotation.
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
#' if (requireNamespace("ggplot2", quietly = TRUE)) {
#'   p <- entropia_plot_coverage(q)
#'   p + ggplot2::labs(title = "Cobertura")
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
  ent_plot_numeric(x, "pct")
  if (!nrow(x)) {
    return(ent_plot_empty("Cobertura del corpus"))
  }
  x$.ent_display <- as.character(x$group)
  fill <- "group"
  if ("group_id" %in% names(x)) {
    fill <- "group_id"
    x$.ent_display <- paste0(x$.ent_display, " [", x$group_id, "]")
  }
  if ("total" %in% names(x)) {
    if (!is.numeric(x$total)) ent_plot_error("total must be numeric.")
    x$pct[!is.finite(x$total) | x$total <= 0] <- NA_real_
  }
  facet <- if (length(unique(x$metric)) > 1L) "metric" else NULL
  ent_plot_bars(x, ".ent_display", "pct", "Cobertura del corpus", fill, facet) +
    ggplot2::scale_y_continuous(labels = ent_pct_labels) +
    ggplot2::labs(y = "Cobertura")
}
