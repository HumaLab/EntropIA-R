# Export / interoperability (Task 22 provenance I/O; Task 24 entropia_export).
#
# Reproducibility sidecar: entropia_analysis_dataset() stamps an
# `entropia_prov` attribute onto every dataset it returns.
# entropia_provenance() reads that stamp back; entropia_write_provenance()
# persists it as a JSON sidecar next to the analysis. The JSON records the
# schema version, source path + content hash, the captured filter expressions,
# the package and R versions, and the build timestamp -- everything needed to
# reconstruct the dataset from the database.

#' Read the provenance stamp of a reproducible dataset
#'
#' Returns the `entropia_prov` attribute attached by
#' [entropia_analysis_dataset()]: a list recording the dataset `name`, the
#' database `schema_version`, the schema `content_hash`, the `source_path`, the
#' captured `filters`, the `package_version`, the `built_at` timestamp and the
#' `r_version`. Aborts with `entropia_error_invalid_argument` when `x` carries
#' no provenance stamp.
#'
#' @param x An object carrying a provenance stamp, e.g. the output of
#'   [entropia_analysis_dataset()].
#' @return A list of class `entropia_provenance`.
#' @examples
#' con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
#'   package = "entropiaR"
#' ))
#' ds <- entropia_analysis_dataset(con, asset_type == "image")
#' entropia_provenance(ds)
#' entropia_disconnect(con)
#' @export
entropia_provenance <- function(x) {
  prov <- attr(x, "entropia_prov", exact = TRUE)
  if (is.null(prov)) {
    ent_abort(
      "entropia_error_invalid_argument",
      c(
        "{.arg x} carries no provenance stamp.",
        i = paste0(
          "Build a reproducible dataset with {.fn entropia_analysis_dataset} ",
          "to attach provenance, then read it back here."
        )
      )
    )
  }
  class(prov) <- c("entropia_provenance", "list")
  prov
}

#' @export
print.entropia_provenance <- function(x, ...) {
  nm <- if (is.null(x$name)) "<unnamed>" else x$name
  cat("entropiaR dataset provenance\n")
  cat("  name:           ", nm, "\n", sep = "")
  ver <- x$schema_version
  if (length(ver) != 1L || is.na(ver)) ver <- "unknown"
  cat("  schema version: ", ver, "\n", sep = "")
  cat("  content hash:   ", x$content_hash, "\n", sep = "")
  cat("  source path:    ", x$source_path, "\n", sep = "")
  if (length(x$filters) > 0L) {
    cat("  filters:        ", paste(x$filters, collapse = "; "), "\n", sep = "")
  }
  cat("  package:        ", x$package_version, "\n", sep = "")
  cat("  built at:       ", x$built_at, "\n", sep = "")
  cat("  R version:      ", x$r_version, "\n", sep = "")
  invisible(x)
}

#' Write a provenance sidecar (JSON)
#'
#' Persists the provenance stamp of a reproducible dataset as a JSON file, the
#' sidecar that travels with the analysis output. `NULL` values are written as
#' JSON `null` and `NA` values as `null`, so the file round-trips through
#' [jsonlite::fromJSON()] back to the same structure (apart from the list
#' class). The file is UTF-8.
#'
#' @param x An object carrying a provenance stamp (see [entropia_provenance()]).
#' @param path Destination file path. Must be a single path.
#' @return The normalized `path`, invisibly.
#' @examples
#' con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
#'   package = "entropiaR"
#' ))
#' ds <- entropia_analysis_dataset(con, asset_type == "image")
#' path <- tempfile(fileext = ".json")
#' entropia_write_provenance(ds, path)
#' readLines(path)
#' entropia_disconnect(con)
#' @export
entropia_write_provenance <- function(x, path) {
  if (!is.character(path) || length(path) != 1L || is.na(path)) {
    ent_abort("entropia_error_invalid_argument", "{.arg path} must be a single path.")
  }
  prov <- entropia_provenance(x)
  json <- jsonlite::toJSON(
    unclass(prov),
    auto_unbox = TRUE,
    pretty = TRUE,
    null = "null",
    na = "null"
  )
  writeLines(json, path, useBytes = TRUE)
  invisible(path)
}

# --- Task 24: entropia_export ------------------------------------------------

# Is the arrow package available? Extracted behind a named internal so the
# missing-dependency error path is testable (tests mock this seam).
ent_arrow_available <- function() {
  requireNamespace("arrow", quietly = TRUE)
}

# Require the arrow package (Suggests) for the parquet/arrow formats, with the
# same clear, actionable missing-dependency error as ent_require_ggplot2() in
# the plotting module.
ent_require_arrow <- function() {
  if (!ent_arrow_available()) {
    ent_abort(
      "entropia_error_missing_dependency",
      c(
        "Exporting to {.code parquet} or {.code arrow} requires the {.pkg arrow} package.",
        i = "Install it with {.code install.packages(\"arrow\")}.",
        i = paste0(
          "Arrow export is optional ({.pkg Suggests}); the {.code csv}, ",
          "{.code tsv}, {.code json} and {.code rds} formats work without it."
        )
      )
    )
  }
  invisible(TRUE)
}

# Validate the export format. Mirrors match.arg() semantics for the default
# argument (the full choice vector resolves to its first element, "csv") but
# carries the package's entropia_error_invalid_argument class and does exact
# matching (no partial matches).
ent_validate_export_format <- function(x) {
  choices <- c("csv", "tsv", "json", "rds", "parquet", "arrow")
  if (length(x) == 1L && !is.na(x) && x %in% choices) {
    return(x)
  }
  if (length(x) > 1L && all(x %in% choices)) {
    return(choices[[1L]])
  }
  ent_abort(
    "entropia_error_invalid_argument",
    c(
      "{.arg format} must be one of {.val {choices}}.",
      i = "Received {.val {x}}."
    )
  )
}

# Validate the destination path: a single non-NA character string.
ent_validate_export_path <- function(path) {
  if (!is.character(path) || length(path) != 1L || is.na(path)) {
    ent_abort(
      "entropia_error_invalid_argument",
      "{.arg path} must be a single destination path."
    )
  }
  normalizePath(path, winslash = "/", mustWork = FALSE)
}

# Validate chunk_size: a single positive whole number.
ent_validate_chunk_size <- function(x) {
  ok <- is.numeric(x) && length(x) == 1L && !is.na(x) &&
    x >= 1L && x <= .Machine$integer.max && x == as.integer(x)
  if (!ok) {
    ent_abort(
      "entropia_error_invalid_argument",
      "{.arg chunk_size} must be a single positive integer (received {.val {x}})."
    )
  }
  as.integer(x)
}

# Deterministic row order for lazy exports: when the rendered SQL carries no
# ORDER BY, arrange by the first column. Queries with an explicit ordering
# (including entropia_search()'s rank ordering) are left untouched. The check
# is deliberately conservative -- any ORDER BY anywhere in the SQL (e.g. inside
# a window function) skips the re-arrange rather than risk producing a double
# ORDER BY.
ent_export_ordered <- function(x) {
  sql <- as.character(dbplyr::sql_render(x))
  if (!grepl("(?i)ORDER[[:space:]]+BY", sql, perl = TRUE)) {
    cols <- colnames(x)
    if (length(cols) > 0L) {
      # Single arrange() call with both columns so dbplyr emits one ORDER BY
      # clause. When only one column exists, it is the sole sort key. Two
      # columns produce a deterministic total order even when the first column
      # has ties (e.g. corpus queries where item_id repeats across assets).
      extra <- if (length(cols) > 1L) list(rlang::sym(cols[[2L]])) else list()
      x <- dplyr::arrange(x, !!rlang::sym(cols[[1L]]), !!!extra)
    }
  }
  x
}

# Serialise one list-column cell for delimited output: NULL/empty -> NA, raw
# (a BLOB cell) -> space-joined bytes, anything else -> JSON.
ent_export_list_scalar <- function(z) {
  if (is.null(z) || length(z) == 0L) {
    return(NA_character_)
  }
  if (is.raw(z)) {
    return(paste(z, collapse = " "))
  }
  jsonlite::toJSON(z, auto_unbox = TRUE)
}

# Convert a data.frame for delimited writing: list-columns become JSON strings
# and BLOB (list-of-raw) columns become space-joined bytes, so
# utils::write.table never sees a type it cannot serialise. Leaves plain atomic
# columns (including integer64) untouched.
ent_prepare_delimited <- function(df) {
  for (nm in names(df)) {
    col <- df[[nm]]
    if (is.list(col) && !is.data.frame(col)) {
      df[[nm]] <- vapply(
        col,
        ent_export_list_scalar,
        character(1),
        USE.NAMES = FALSE
      )
    }
  }
  df
}

# Stream a lazy query to a delimited file in bounded chunks: dbSendQuery +
# fetch(n), the header written once, rows appended chunk by chunk. Never
# collects the whole result into memory. The query must already be
# deterministically ordered (see ent_export_ordered()).
ent_export_delimited_lazy <- function(x, path, sep, chunk_size) {
  con <- dbplyr::remote_con(x)
  sql <- as.character(dbplyr::sql_render(x))
  res <- DBI::dbSendQuery(con, sql)
  on.exit(DBI::dbClearResult(res), add = TRUE)
  chunk <- ent_prepare_delimited(DBI::dbFetch(res, n = chunk_size))
  utils::write.table(chunk, path,
    sep = sep, row.names = FALSE, quote = TRUE,
    qmethod = "double"
  )
  while (nrow(chunk) > 0L) {
    chunk <- ent_prepare_delimited(DBI::dbFetch(res, n = chunk_size))
    if (nrow(chunk) > 0L) {
      utils::write.table(
        chunk, path,
        sep = sep, row.names = FALSE, quote = TRUE,
        col.names = FALSE, append = TRUE, qmethod = "double"
      )
    }
  }
  invisible(path)
}

# Write a materialised data.frame to a delimited file in one pass. qmethod =
# "double" writes RFC-4180 quote escaping, so fields that contain both embedded
# quotes and newlines (e.g. extraction text) round-trip through base read.csv
# and every standards-compliant reader -- the default "escape" method mangles
# them in R's own parser.
ent_export_delimited_df <- function(x, path, sep) {
  df <- ent_prepare_delimited(tibble::as_tibble(x))
  utils::write.table(df, path,
    sep = sep, row.names = FALSE, quote = TRUE,
    qmethod = "double"
  )
  invisible(path)
}

# JSON export: a single pretty JSON document (rows as objects). jsonlite
# serialises list-columns natively, so a collected tibble round-trips through
# jsonlite::fromJSON with its structure.
ent_export_json <- function(x, path) {
  df <- if (inherits(x, "tbl_sql")) dplyr::collect(x) else x
  json <- jsonlite::toJSON(df, dataframe = "rows", pretty = TRUE, na = "null")
  writeLines(json, path, useBytes = TRUE)
  invisible(path)
}

# RDS export: saveRDS of the data. A lazy input is collected first (RDS is a
# whole-object format; there is no streaming). A materialised entropia_dataset
# round-trips with its class and provenance attribute intact.
ent_export_rds <- function(x, path) {
  obj <- if (inherits(x, "tbl_sql")) dplyr::collect(x) else x
  saveRDS(obj, path)
  invisible(path)
}

# Parquet/Arrow export: requires the arrow package (Suggests). Collects a lazy
# input (these are whole-file formats, not streamed) and writes a single file.
ent_export_arrow <- function(x, path, format) {
  ent_require_arrow()
  df <- if (inherits(x, "tbl_sql")) dplyr::collect(x) else x
  df <- as.data.frame(ent_prepare_delimited(tibble::as_tibble(df)))
  if (identical(format, "parquet")) {
    arrow::write_parquet(df, path)
  } else {
    arrow::write_feather(df, path)
  }
  invisible(path)
}

#' Export data to a file
#'
#' Writes a data frame/tibble (or a lazy query) to a file in one of six
#' formats. `csv`, `tsv`, `json` and `rds` always work; `parquet` and `arrow`
#' (Feather v2) require the optional `arrow` package. A lazy `tbl_sql` input is
#' exported without being collected into memory for the delimited formats: the
#' query is streamed in bounded chunks via `DBI::dbSendQuery` +
#' `DBI::dbFetch`, so exporting a large corpus to CSV stays flat in memory.
#' `json`, `rds`, `parquet` and `arrow` are whole-file formats and collect the
#' query first.
#'
#' Lazy queries are exported in a deterministic row order: when the rendered
#' SQL carries no `ORDER BY`, the export arranges by the first column before
#' streaming. Queries with an explicit ordering (e.g. [entropia_search()]'s
#' rank order, or `dplyr::arrange()` applied first) are exported in that order.
#' Materialised data is written in the order it was given.
#'
#' The column contract is NOT applied by the export: a lazy query exports the
#' raw values SQLite stores (epoch timestamps as integers, JSON-in-TEXT as
#' text). Collect with [entropia_collect()] first -- and pass the result as a
#' tibble -- to export typed values (`POSIXct` timestamps and JSON list-columns).
#'
#' @param x A data frame/tibble or a lazy `tbl_sql` table (e.g. from
#'   [entropia_corpus()] or [entropia_items()]).
#' @param path Destination file path (a single path; parent directories are not
#'   created).
#' @param format One of `"csv"`, `"tsv"`, `"json"`, `"rds"`, `"parquet"` or
#'   `"arrow"`.
#' @param chunk_size Rows fetched per chunk when streaming a lazy input to a
#'   delimited format. Default `1000L`.
#' @return The normalized `path`, invisibly.
#' @export
#' @examples
#' tmp <- tempfile(fileext = ".csv")
#' entropia_export(tibble::tibble(id = 1:2, label = c("a", "b")), tmp)
#' read.csv(tmp)
entropia_export <- function(x, path,
                            format = c("csv", "tsv", "json", "rds", "parquet", "arrow"),
                            chunk_size = 1000L) {
  format <- ent_validate_export_format(format)
  path <- ent_validate_export_path(path)
  chunk_size <- ent_validate_chunk_size(chunk_size)

  lazy <- inherits(x, "tbl_sql")
  if (lazy) {
    ent_require_conn(dbplyr::remote_con(x))
    x <- ent_export_ordered(x)
  } else if (!inherits(x, "data.frame")) {
    ent_abort(
      "entropia_error_invalid_argument",
      c(
        "{.arg x} must be a data frame/tibble or a lazy {.cls tbl_sql} table.",
        i = paste0(
          "Create a lazy table with an accessor such as {.fn entropia_corpus}, ",
          "or collect it first with {.fn entropia_collect}."
        )
      )
    )
  }

  switch(format,
    csv = {
      if (lazy) {
        ent_export_delimited_lazy(x, path, ",", chunk_size)
      } else {
        ent_export_delimited_df(x, path, ",")
      }
    },
    tsv = {
      if (lazy) {
        ent_export_delimited_lazy(x, path, "\t", chunk_size)
      } else {
        ent_export_delimited_df(x, path, "\t")
      }
    },
    json = ent_export_json(x, path),
    rds = ent_export_rds(x, path),
    parquet = ent_export_arrow(x, path, "parquet"),
    arrow = ent_export_arrow(x, path, "arrow")
  )
  invisible(path)
}
