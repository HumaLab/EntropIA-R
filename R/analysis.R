# Analysis layer (Tasks 20-21): pure functions on collected tibbles.
#
# These helpers operate on materialised tibbles (the output of
# entropia_collect() or dplyr::collect()), never on lazy tables: temporal
# bucketing and word counting are R-side computations. Argument validation
# carries the entropia_error_invalid_argument class like the rest of the
# package, and column references resolve through tidyselect (bare names,
# strings and character vectors all work).

# Require a data frame/tibble. A lazy tbl_sql is not a data.frame, so it is
# rejected here with guidance: analysis runs on collected rows.
ent_require_tibble <- function(x) {
  if (!inherits(x, "data.frame")) {
    ent_abort(
      "entropia_error_invalid_argument",
      c(
        "{.arg x} must be a data frame or tibble.",
        i = paste0(
          "Analysis functions run on collected rows; call ",
          "{.fn entropia_collect} (or {.fn dplyr::collect}) on a lazy table first."
        )
      )
    )
  }
  x
}

# Resolve a tidyselect expression to column names of `x`. tidyselect's own
# errors (unknown columns, empty selection) are caught and rethrown with the
# package's error class and an actionable list of available columns.
ent_select_cols <- function(x, quo, arg, exactly = NULL) {
  sel <- tryCatch(
    tidyselect::eval_select(quo, data = x),
    error = function(e) NULL
  )
  if (is.null(sel)) {
    ent_abort(
      "entropia_error_invalid_argument",
      c(
        "{.arg {arg}} must select existing column(s) of {.arg x}.",
        i = "Columns available: {.val {names(x)}}."
      )
    )
  }
  if (!is.null(exactly) && length(sel) != exactly) {
    ent_abort(
      "entropia_error_invalid_argument",
      c(
        "{.arg {arg}} must select exactly {exactly} column{?s}.",
        i = "It selected: {.val {names(sel)}}."
      )
    )
  }
  names(sel)
}

# Floor POSIXct timestamps to the start of their `unit` bucket. Day and longer
# units are wall-clock in the vector's timezone (UTC for EntropIA data);
# second/minute/hour are exact epoch truncations. Weeks start on Monday (the
# base cut.POSIXt convention).
ent_floor_date <- function(d, unit) {
  tz <- attr(d, "tzone") %||% "UTC"
  switch(unit,
    second = as.POSIXct(trunc(as.numeric(d)), origin = "1970-01-01", tz = tz),
    minute = as.POSIXct(trunc(as.numeric(d) / 60) * 60, origin = "1970-01-01", tz = tz),
    hour = as.POSIXct(trunc(as.numeric(d) / 3600) * 3600, origin = "1970-01-01", tz = tz),
    day = as.POSIXct(format(d, "%Y-%m-%d"), tz = tz),
    week = as.POSIXct(as.character(cut(d, "weeks")), tz = tz),
    month = as.POSIXct(format(d, "%Y-%m-01"), tz = tz),
    quarter = {
      qm <- 1L + 3L * ((as.integer(format(d, "%m")) - 1L) %/% 3L)
      as.POSIXct(sprintf("%04d-%02d-01", as.integer(format(d, "%Y")), qm), tz = tz)
    },
    year = as.POSIXct(format(d, "%Y-01-01"), tz = tz)
  )
}

#' Temporal profile (counts by time bucket)
#'
#' `r lifecycle::badge("experimental")`
#'
#' Counts the rows of a collected tibble by a date/time column, bucketed to a
#' chosen time unit. This is an R-side analysis helper: pass a materialised
#' tibble (e.g. the output of [entropia_collect()], where timestamps are
#' `POSIXct`). `NA` timestamps are excluded -- a row with an unknown date
#' cannot be placed in time; grouping columns from `by` keep `NA` as their own
#' group, following `dplyr` semantics.
#'
#' The returned bucket column carries the name of `date_var` and holds the
#' start of each unit (`POSIXct`, e.g. midnight for `unit = "day"`). Rows are
#' ordered by the `by` columns then the bucket, deterministically. Weeks start
#' on Monday.
#'
#' @param x A data frame or tibble of collected rows.
#' @param date_var A column of `POSIXct` (or `Date`) timestamps, selected by
#'   name or bare (tidyselect).
#' @param unit The time bucket: `"second"`, `"minute"`, `"hour"`, `"day"`,
#'   `"week"` (Monday-start), `"month"`, `"quarter"` or `"year"`. Default
#'   `"month"`.
#' @param by Optional column(s) to break the counts by, selected by name or
#'   bare (tidyselect). `NULL` (default) produces a single time series.
#' @return A tibble with the bucket column, the `by` columns (when given), and
#'   a count column `n`.
#' @examples
#' con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
#'   package = "entropiaR"
#' ))
#' items <- entropia_collect(entropia_items(con))
#' entropia_temporal_profile(items, created_at, unit = "month")
#' entropia_disconnect(con)
#' @export
entropia_temporal_profile <- function(x, date_var, unit = "month", by = NULL) {
  x <- ent_require_tibble(x)
  unit <- ent_validate_choice(
    unit,
    c("second", "minute", "hour", "day", "week", "month", "quarter", "year"),
    "unit"
  )
  date_col <- ent_select_cols(x, rlang::enquo(date_var), "date_var", exactly = 1L)
  by_cols <- ent_select_cols(x, rlang::enquo(by), "by")
  if ("n" %in% c(date_col, by_cols)) {
    ent_abort(
      "entropia_error_invalid_argument",
      paste0(
        "{.code n} is reserved for the count column; rename the column ",
        "selected by {.arg date_var} or {.arg by}."
      )
    )
  }

  d <- x[[date_col]]
  if (!inherits(d, "POSIXct") && !inherits(d, "Date")) {
    ent_abort(
      "entropia_error_invalid_argument",
      c(
        "{.arg date_var} ({.val {date_col}}) must be {.cls POSIXct} or {.cls Date}.",
        i = paste0(
          "It is {.cls {class(d)}}. Collect with {.fn entropia_collect} ",
          "(timestamps become {.cls POSIXct}), or convert with ",
          "{.fn entropia_datetime} first."
        )
      )
    )
  }
  if (inherits(d, "Date")) d <- as.POSIXct(d)

  keep <- !is.na(d)
  d <- d[keep]
  x <- x[keep, , drop = FALSE]

  bucket <- ent_floor_date(d, unit)
  out <- stats::setNames(tibble::tibble(bucket), date_col)
  if (length(by_cols) > 0L) {
    out <- dplyr::bind_cols(out, x[by_cols])
  }
  out$n <- 1L
  out <- dplyr::summarise(
    dplyr::group_by(out, dplyr::across(dplyr::all_of(c(by_cols, date_col)))),
    n = dplyr::n(),
    .groups = "drop"
  )
  dplyr::arrange(out, !!!rlang::syms(c(by_cols, date_col)))
}

# Words in a character scalar: runs of non-whitespace tokens. Empty/whitespace
# text is 0 words; NA is NA (the caller's NA policy). Punctuation stays
# attached to its token, so "Compañeros," counts as one word.
ent_n_words <- function(z) {
  if (is.na(z)) {
    return(NA_integer_)
  }
  z <- trimws(z)
  if (!nzchar(z)) {
    return(0L)
  }
  lengths(gregexpr("[^[:space:]]+", z))
}

#' Document lengths (chars/words per row)
#'
#' `r lifecycle::badge("experimental")`
#'
#' Appends character and word counts per row of a collected tibble. Each row
#' is treated as one document. `NA` text yields `NA` counts; empty or
#' whitespace-only text yields 0 chars and 0 words. Words are
#' whitespace-separated tokens (multiple spaces collapse; punctuation stays
#' attached to its token).
#'
#' @param x A data frame or tibble of collected rows.
#' @param text_var Column holding the document text, selected by name or bare
#'   (tidyselect). Default `"text"`.
#' @return `x` with two appended columns: `n_chars` (characters) and `n_words`
#'   (whitespace-separated tokens).
#' @examples
#' con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
#'   package = "entropiaR"
#' ))
#' text_layer <- entropia_collect(entropia_text(con))
#' entropia_document_lengths(text_layer)
#' entropia_disconnect(con)
#' @export
entropia_document_lengths <- function(x, text_var = "text") {
  x <- ent_require_tibble(x)
  text_col <- ent_select_cols(x, rlang::enquo(text_var), "text_var", exactly = 1L)
  reserved <- intersect(c("n_chars", "n_words"), names(x))
  if (length(reserved) > 0L) {
    ent_abort(
      "entropia_error_invalid_argument",
      c(
        paste0(
          "{.arg x} already has column{?s} reserved by ",
          "{.fn entropia_document_lengths}: {.val {reserved}}."
        ),
        i = "Drop or rename them before calling {.fn entropia_document_lengths}."
      )
    )
  }
  d <- x[[text_col]]
  if (is.list(d)) {
    ent_abort(
      "entropia_error_invalid_argument",
      c(
        "{.arg text_var} ({.val {text_col}}) must be a character column of text.",
        i = "It is a list-column; pass a plain text column instead."
      )
    )
  }
  d <- as.character(d)
  out <- tibble::as_tibble(x)
  out$n_chars <- nchar(d)
  out$n_words <- vapply(d, ent_n_words, integer(1), USE.NAMES = FALSE)
  out
}

# --- Task 21: frequency + collection comparison ------------------------------

# Require specific columns on an analysis tibble. The frequency helpers need a
# fixed shape (entity_type/value, topic name); missing columns abort with the
# package's error class and an actionable list of what is actually present.
ent_require_analysis_cols <- function(x, cols, fn) {
  missing <- setdiff(cols, names(x))
  if (length(missing) > 0L) {
    ent_abort(
      "entropia_error_invalid_argument",
      c(
        paste0(
          "{.fn {fn}} requires {length(cols)} column{?s} on {.arg x}: ",
          "{.val {cols}}."
        ),
        i = "Missing here: {.val {missing}}.",
        i = "Columns available: {.val {names(x)}}."
      )
    )
  }
  invisible(x)
}

#' Entity frequency (top entities by type)
#'
#' `r lifecycle::badge("experimental")`
#'
#' Counts entity occurrences from a collected entities tibble: for every
#' distinct `entity_type` x `value` pair, the number of rows carrying it. The
#' result is ordered by `entity_type` then descending count, so the top
#' entities of each type read off the top of each block. Pass the collected
#' output of [entropia_entities()] directly, or join it to `items` and
#' `collections` first and pass `by` to break the counts down further (e.g. by
#' `collection_name`). Soft-deleted rows are whatever the input carries -- use
#' `include_deleted = TRUE` on [entropia_entities()] to count them.
#'
#' @param x A data frame or tibble of collected entity rows, carrying
#'   `entity_type` and `value` columns.
#' @param by Optional column(s) to break the counts by, selected by name or
#'   bare (tidyselect). `NULL` (default) produces one row per
#'   `entity_type` x `value`.
#' @return A tibble with the `by` columns (when given), `entity_type`, `value`
#'   and `n` (row count), ordered by `entity_type` then `n` descending then
#'   `value`.
#' @examples
#' con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
#'   package = "entropiaR"
#' ))
#' entities <- entropia_collect(entropia_entities(con))
#' entropia_entity_frequency(entities)
#' entropia_disconnect(con)
#' @export
entropia_entity_frequency <- function(x, by = NULL) {
  x <- ent_require_tibble(x)
  ent_require_analysis_cols(x, c("entity_type", "value"), "entropia_entity_frequency")
  by_cols <- ent_select_cols(x, rlang::enquo(by), "by")
  if ("n" %in% by_cols) {
    ent_abort(
      "entropia_error_invalid_argument",
      paste0(
        "{.code n} is reserved for the count column; rename the column ",
        "selected by {.arg by}."
      )
    )
  }
  groups <- c(by_cols, "entity_type", "value")
  out <- dplyr::summarise(
    dplyr::group_by(x, dplyr::across(dplyr::all_of(groups))),
    n = dplyr::n(),
    .groups = "drop"
  )
  dplyr::arrange(
    out,
    !!!rlang::syms(by_cols),
    .data$entity_type,
    dplyr::desc(.data$n),
    .data$value
  )
}

#' Topic frequency (items per topic)
#'
#' `r lifecycle::badge("experimental")`
#'
#' Counts rows per topic from a collected tibble carrying a topic `name`
#' column. The natural input is `item_topics` joined to `topics` (e.g.
#' `dplyr::left_join(entropia_collect(entropia_item_topics(con)),
#' entropia_collect(entropia_topics(con)), by = c("topic_id" = "id"))`).
#' Because `item_topics` has a `UNIQUE(item_id, topic_id)` constraint, counting
#' rows per topic counts items per topic. The result is ordered by descending
#' count then topic name (deterministic).
#'
#' @param x A data frame or tibble with a `name` column holding topic names.
#' @param by Optional column(s) to break the counts by, selected by name or
#'   bare (tidyselect). `NULL` (default) produces one row per topic.
#' @return A tibble with the `by` columns (when given), `name` and `n` (item
#'   count), ordered by `n` descending then `name`.
#' @examples
#' con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
#'   package = "entropiaR"
#' ))
#' item_topics <- entropia_collect(entropia_item_topics(con))
#' topics <- entropia_collect(entropia_topics(con))
#' joined <- dplyr::left_join(item_topics, topics, by = c("topic_id" = "id"))
#' entropia_topic_frequency(joined)
#' entropia_disconnect(con)
#' @export
entropia_topic_frequency <- function(x, by = NULL) {
  x <- ent_require_tibble(x)
  ent_require_analysis_cols(x, "name", "entropia_topic_frequency")
  by_cols <- ent_select_cols(x, rlang::enquo(by), "by")
  if ("n" %in% by_cols) {
    ent_abort(
      "entropia_error_invalid_argument",
      paste0(
        "{.code n} is reserved for the count column; rename the column ",
        "selected by {.arg by}."
      )
    )
  }
  groups <- c(by_cols, "name")
  out <- dplyr::summarise(
    dplyr::group_by(x, dplyr::across(dplyr::all_of(groups))),
    n = dplyr::n(),
    .groups = "drop"
  )
  dplyr::arrange(out, !!!rlang::syms(by_cols), dplyr::desc(.data$n), .data$name)
}

#' Compare collections (per-collection summary)
#'
#' `r lifecycle::badge("experimental")`
#'
#' Summarises a collected tibble one row per collection. The natural input is
#' the collected corpus (`dplyr::collect(entropia_corpus(con))`), which carries
#' `collection_name`, `item_id` and `asset_id`; pass `by` to group by a
#' different collection column (e.g. `collection_id`).
#'
#' Each row reports `n` (rows of `x` in that collection) plus `n_items` and
#' `n_assets` (distinct `item_id` / `asset_id` values, `NA` excluded) when the
#' input carries those columns. On the collected corpus `n` equals the number
#' of assets in the collection. Rows are ordered by the collection column
#' (deterministic).
#'
#' @param x A data frame or tibble with a collection column.
#' @param by The collection column, selected by name or bare (tidyselect).
#'   Default `"collection_name"`.
#' @return A tibble with the `by` column, `n_items`/`n_assets` (when `x` carries
#'   those id columns) and `n`, ordered by the collection column.
#' @examples
#' con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
#'   package = "entropiaR"
#' ))
#' corpus <- entropia_collect(entropia_corpus(con))
#' entropia_compare_collections(corpus)
#' entropia_disconnect(con)
#' @export
entropia_compare_collections <- function(x, by = "collection_name") {
  x <- ent_require_tibble(x)
  by_col <- ent_select_cols(x, rlang::enquo(by), "by", exactly = 1L)
  if (identical(by_col, "n")) {
    ent_abort(
      "entropia_error_invalid_argument",
      paste0(
        "{.code n} is reserved for the row-count column; rename the column ",
        "selected by {.arg by}."
      )
    )
  }
  has_item <- "item_id" %in% names(x)
  has_asset <- "asset_id" %in% names(x)
  if (has_item && "n_items" %in% names(x)) {
    ent_abort(
      "entropia_error_invalid_argument",
      c(
        paste0(
          "{.arg x} already has a {.code n_items} column, which ",
          "{.fn entropia_compare_collections} creates from {.code item_id}."
        ),
        i = "Drop or rename it before calling {.fn entropia_compare_collections}."
      )
    )
  }
  if (has_asset && "n_assets" %in% names(x)) {
    ent_abort(
      "entropia_error_invalid_argument",
      c(
        paste0(
          "{.arg x} already has a {.code n_assets} column, which ",
          "{.fn entropia_compare_collections} creates from {.code asset_id}."
        ),
        i = "Drop or rename it before calling {.fn entropia_compare_collections}."
      )
    )
  }

  sum_exprs <- list()
  if (has_item) {
    sum_exprs[["n_items"]] <- rlang::expr(dplyr::n_distinct(.data$item_id, na.rm = TRUE))
  }
  if (has_asset) {
    sum_exprs[["n_assets"]] <- rlang::expr(dplyr::n_distinct(.data$asset_id, na.rm = TRUE))
  }
  sum_exprs[["n"]] <- rlang::expr(dplyr::n())

  out <- dplyr::summarise(
    dplyr::group_by(x, dplyr::across(dplyr::all_of(by_col))),
    !!!sum_exprs,
    .groups = "drop"
  )
  dplyr::arrange(out, !!!rlang::syms(by_col))
}

# --- Task 22: reproducible datasets + provenance ------------------------------

# Validate the `name` argument of entropia_analysis_dataset(): NULL (unnamed)
# or a single non-NA character string.
ent_validate_dataset_name <- function(name) {
  if (is.null(name)) {
    return(name)
  }
  if (!is.character(name) || length(name) != 1L || is.na(name)) {
    ent_abort(
      "entropia_error_invalid_argument",
      "{.arg name} must be {.code NULL} or a single name for the dataset."
    )
  }
  name
}

#' Build a reproducible analysis dataset
#'
#' `r lifecycle::badge("experimental")`
#'
#' The dataset boundary of the package: assembles the lazy corpus
#' ([entropia_corpus()]), applies any filter expressions passed in `...`, and
#' materialises the result with a deterministic row order (arranged by
#' `asset_id`). The returned tibble carries class `entropia_dataset` and an
#' `entropia_prov` attribute recording everything needed to reconstruct the
#' dataset:
#'
#' - `name`: the human label passed to `name` (`NULL` for unnamed);
#' - `schema_version`: the database schema head (e.g. `"0029_rag_chunks"`);
#' - `content_hash`: the connection's schema content hash (see
#'   [entropia_connect()]);
#' - `source_path`: the database file the dataset was built from;
#' - `filters`: the deparsed filter expressions captured from `...`;
#' - `package_version`: the entropiaR version used;
#' - `built_at`: the build timestamp (ISO-8601, UTC);
#' - `r_version`: the R version used.
#'
#' Building the same dataset twice against an unchanged database yields
#' byte-identical rows (deterministic ordering) and identical provenance apart
#' from `built_at`. Read the stamp with [entropia_provenance()] and persist it
#' as a JSON sidecar with [entropia_write_provenance()].
#'
#' @param con A connection returned by [entropia_connect()].
#' @param ... Filter expressions applied to the corpus, e.g.
#'   `asset_type == "image"`. Column names resolve against the lazy corpus
#'   (see [entropia_corpus()] for the full column set). Must be unnamed.
#' @param name Optional human-readable label stored in the provenance.
#' @return A [tibble::tibble()] of class `entropia_dataset`, one row per asset,
#'   with the `entropia_prov` attribute.
#' @examples
#' con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
#'   package = "entropiaR"
#' ))
#' ds <- entropia_analysis_dataset(con, asset_type == "pdf", name = "PDF corpus")
#' entropia_provenance(ds)
#' entropia_disconnect(con)
#' @export
entropia_analysis_dataset <- function(con, ..., name = NULL) {
  ent_require_conn(con)
  name <- ent_validate_dataset_name(name)
  filters <- rlang::enquos(...)
  if (any(rlang::names2(filters) != "")) {
    ent_abort(
      "entropia_error_invalid_argument",
      "{.arg ...} filter expressions must be unnamed (a name was provided)."
    )
  }

  corpus <- entropia_corpus(con)
  if (length(filters) > 0L) {
    corpus <- dplyr::filter(corpus, !!!filters)
  }
  # Deterministic row order: arrange on the corpus's always-present asset_id so
  # identical inputs yield identical datasets regardless of the physical row
  # order SQLite happens to return. No sampling, no dependence on row order.
  corpus <- dplyr::arrange(corpus, .data$asset_id)
  data <- entropia_collect(corpus)

  prov <- list(
    name = name,
    schema_version = ent_attr(con, "schema_version"),
    content_hash = ent_attr(con, "content_hash"),
    source_path = ent_attr(con, "path"),
    filters = vapply(filters, rlang::as_label, character(1), USE.NAMES = FALSE),
    package_version = as.character(utils::packageVersion("entropiaR")),
    built_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3Z", tz = "UTC"),
    r_version = R.version.string
  )
  attr(data, "entropia_prov") <- prov
  class(data) <- c("entropia_dataset", class(data))
  data
}

#' @export
print.entropia_dataset <- function(x, ...) {
  prov <- attr(x, "entropia_prov", exact = TRUE)
  nm <- if (is.null(prov) || is.null(prov$name)) "<unnamed>" else prov$name
  cat(sprintf("entropia_dataset: %s\n", nm))
  if (!is.null(prov)) {
    ver <- prov$schema_version
    if (length(ver) != 1L || is.na(ver)) ver <- "unknown"
    hash <- prov$content_hash
    hash_short <- if (length(hash) != 1L || is.na(hash)) "n/a" else substr(hash, 1L, 12L)
    cat(sprintf("  schema: %s  content: %s\n", ver, hash_short))
    if (length(prov$filters) > 0L) {
      cat("  filters: ", paste(prov$filters, collapse = "; "), "\n", sep = "")
    }
  }
  nxt <- x
  class(nxt) <- setdiff(class(x), "entropia_dataset")
  print(nxt, ...)
  invisible(x)
}

#' @exportS3Method pillar::glimpse
glimpse.entropia_dataset <- function(x, ...) {
  prov <- attr(x, "entropia_prov", exact = TRUE)
  nm <- if (is.null(prov) || is.null(prov$name)) "<unnamed>" else prov$name
  cat(sprintf("entropia_dataset: %s\n", nm))
  nxt <- x
  class(nxt) <- setdiff(class(x), "entropia_dataset")
  dplyr::glimpse(nxt, ...)
}

#' @exportS3Method tibble::as_tibble
as_tibble.entropia_dataset <- function(x, ...) {
  attr(x, "entropia_prov") <- NULL
  class(x) <- setdiff(class(x), "entropia_dataset")
  tibble::as_tibble(x, ...)
}
