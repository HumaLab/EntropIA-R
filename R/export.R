# Export / interoperability (Task 22 provenance I/O; Task 24 entropia_export).
#
# Reproducibility sidecar: entropia_analysis_dataset() stamps an
# `entropia_prov` attribute onto every dataset it returns.
# entropia_provenance() reads that stamp back; entropia_write_provenance()
# persists it as a JSON sidecar next to the analysis. The JSON records the
# schema version, source path and schema hash, the captured filter expressions,
# the package and R versions, and the build timestamp -- everything needed to
# reconstruct the dataset from the database.

#' Read the provenance stamp of a reproducible dataset
#'
#' Returns the `entropia_prov` attribute attached by
#' [entropia_analysis_dataset()]: a list recording the dataset `name`, the
#' database `schema_version`, the `schema_hash`, the `source_path`, the
#' captured `filters`, the `package_version`, the `built_at` timestamp and the
#' `r_version`. Aborts with `entropia_error_invalid_argument` when `x` carries
#' no provenance stamp. The current data digest is recomputed. Changed values,
#' classes, columns or row order yield `scope = "derived"` and `query = NULL`;
#' `origin` retains the original digest, SQL and selection recipe. Origin SQL
#' is not represented as a recipe for transformed rows.
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
  ent_require_tibble(x)
  current <- ent_dataset_hash(x)
  if (is.null(prov$origin)) {
    prov$origin <- list(
      dataset_sha256 = prov$dataset_sha256,
      query = prov$query, selection = prov$selection
    )
  }
  prov$scope <- if (identical(current, prov$origin$dataset_sha256)) "origin" else "derived"
  prov$dataset_sha256 <- current
  if (prov$scope == "derived") prov$query <- NULL
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
  cat("  schema hash:    ", x$schema_hash, "\n", sep = "")
  cat("  dataset hash:   ", x$dataset_sha256, "\n", sep = "")
  cat("  scope:          ", x$scope, "\n", sep = "")
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
#' @param redact Suppress source paths and free-form SQL/filter/name fields
#'   which may contain paths, including the origin recipe.
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
entropia_write_provenance <- function(x, path, redact = FALSE) {
  if (!is.character(path) || length(path) != 1L || is.na(path) || !nzchar(path)) {
    ent_abort("entropia_error_invalid_argument", "{.arg path} must be a single path.")
  }
  if (!is.logical(redact) || length(redact) != 1L || is.na(redact)) {
    ent_abort("entropia_error_invalid_argument", "{.arg redact} must be TRUE or FALSE.")
  }
  prov <- entropia_provenance(x)
  if (redact) {
    prov$source_path <- NULL
    prov$query <- NULL
    prov$filters <- NULL
    prov$name <- NULL
    prov$origin$query <- NULL
    prov$selection <- NULL
    prov$origin$selection <- NULL
    prov$redacted <- TRUE
  }
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

# Validate the destination path: a single non-NA non-empty character string.
ent_validate_export_path <- function(path) {
  if (!is.character(path) || length(path) != 1L || is.na(path) || !nzchar(path)) {
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

# Keep dbplyr's structural ordering, never infer it from rendered SQL.
# SQLite orders all storage types, including BLOBs, lexicographically.
ent_export_ordered <- function(x, order_by = NULL) {
  cols <- colnames(x)
  ent_export_validate_order(order_by, cols)
  prior <- x$lazy_query$order_by %||% list()
  if (!is.null(order_by)) prior <- rlang::syms(order_by)
  dplyr::arrange(x, !!!prior, !!!rlang::syms(cols))
}

ent_export_validate_order <- function(order_by, cols) {
  if (!is.null(order_by) && (!is.character(order_by) || anyNA(order_by) ||
    !length(order_by) || anyDuplicated(order_by) || !all(order_by %in% cols))) {
    ent_abort(
      "entropia_error_invalid_argument",
      "{.arg order_by} must be NULL or unique existing column names."
    )
  }
  invisible(order_by)
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
#
# Embedding BLOB columns (4096-byte f32 vectors) produce long strings per row
# under the space-join representation -- a thousand such rows produce ~10 MB of
# serialised bytes, which is manageable for occasional exports but not for
# streaming the full embedding table. Accessors exclude the `embedding` column
# by default (select with `any_of("embedding")`), and direct collect+export
# with `with_vector = TRUE` carries the explicit opt-in. Use parquet/arrow/rds
# for bulk embedding export.
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

# Quote every field (write.table quote=TRUE) with RFC-4180 doubling.
# Convert to UTF-8 bytes before as.character can emit <U+XXXX> under LC_ALL=C.
ent_quote_csv <- function(x) {
  x <- if (is.character(x)) {
    ifelse(is.na(x), "NA", x)
  } else {
    ifelse(is.na(x), "NA", as.character(x))
  }
  x <- enc2utf8(x)
  paste0('"', gsub('"', '""', x, fixed = TRUE), '"')
}

ent_delimited_lines <- function(df, sep, header) {
  rows <- character()
  if (isTRUE(header)) {
    rows <- paste(ent_quote_csv(names(df)), collapse = sep)
  }
  if (nrow(df) > 0L) {
    cells <- lapply(df, function(col) {
      if (inherits(col, "POSIXt")) col <- format(col, tz = "UTC")
      ent_quote_csv(col)
    })
    rows <- c(rows, do.call(paste, c(cells, list(sep = sep))))
  }
  rows
}

ent_write_utf8_lines <- function(lines, con) {
  if (!length(lines)) {
    return(invisible(NULL))
  }
  nl <- as.raw(10L)
  for (line in lines) {
    writeBin(c(charToRaw(enc2utf8(line)), nl), con)
  }
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
  output <- file(path, open = "wb")
  on.exit(close(output), add = TRUE)
  chunk <- ent_prepare_delimited(DBI::dbFetch(res, n = chunk_size))
  ent_write_utf8_lines(ent_delimited_lines(chunk, sep, TRUE), output)
  while (nrow(chunk) > 0L) {
    chunk <- ent_prepare_delimited(DBI::dbFetch(res, n = chunk_size))
    if (nrow(chunk) > 0L) {
      ent_write_utf8_lines(ent_delimited_lines(chunk, sep, FALSE), output)
    }
  }
  invisible(path)
}

# Write a materialised data.frame to a delimited file in one pass. Fields that
# contain both embedded quotes and newlines (e.g. extraction text) round-trip
# through base read.csv -- RFC-4180 doubling.
ent_export_delimited_df <- function(x, path, sep) {
  df <- ent_prepare_delimited(tibble::as_tibble(x))
  output <- file(path, open = "wb")
  on.exit(close(output), add = TRUE)
  ent_write_utf8_lines(ent_delimited_lines(df, sep, TRUE), output)
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
  # Don't flatten list/raw columns for arrow/parquet: the format handles them
  # natively (embeddings round-trip as binary arrays, not character strings).
  df <- tibble::as_tibble(df)
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
#' Lazy queries retain ordering recorded in dbplyr's `lazy_query$order_by`,
#' with all projected columns appended as tie-breakers. SQLite compares BLOBs
#' bytewise. Ordering hidden inside opaque SQL or unknown query objects cannot
#' be recovered: supply `order_by` explicitly in that case. Identical projected
#' rows are interchangeable. Materialised data retains its input order unless
#' `order_by` is supplied; list columns cannot be explicit in-memory sort keys.
#' CSV and TSV use one UTF-8 file connection for the entire export.
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
#' @param order_by Optional character vector of primary ordering columns.
#'   All comparable output columns are appended as tie-breakers.
#' @return The normalized `path`, invisibly.
#' @export
#' @examples
#' tmp <- tempfile(fileext = ".csv")
#' entropia_export(tibble::tibble(id = 1:2, label = c("a", "b")), tmp)
#' read.csv(tmp)
entropia_export <- function(x, path,
                            format = c("csv", "tsv", "json", "rds", "parquet", "arrow"),
                            chunk_size = 1000L, order_by = NULL) {
  format <- ent_validate_export_format(format)
  path <- ent_validate_export_path(path)
  chunk_size <- ent_validate_chunk_size(chunk_size)

  lazy <- inherits(x, "tbl_sql")
  if (lazy) {
    ent_require_conn(dbplyr::remote_con(x))
    x <- ent_export_ordered(x, order_by)
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

  if (!lazy) {
    ent_export_validate_order(order_by, names(x))
    if (!is.null(order_by)) {
      comparable <- names(x)[vapply(x, function(z) is.atomic(z) && is.null(dim(z)), logical(1))]
      if (!all(order_by %in% comparable)) {
        ent_abort(
          "entropia_error_invalid_argument",
          "In-memory ordering requires atomic vector columns."
        )
      }
      x <- dplyr::arrange(x, !!!rlang::syms(unique(c(order_by, comparable))))
    }
    if (!is.null(attr(x, "entropia_prov", exact = TRUE))) {
      attr(x, "entropia_prov") <- unclass(entropia_provenance(x))
    }
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
