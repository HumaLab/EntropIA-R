# entropia_collect: typed materialisation.
#
# Accessors return lazy tbl_sql so SQLite does the filtering and joining;
# entropia_collect() is the typed materialisation step. It collects the rows
# and applies the column contract from inst/schemas/manifest.json:
#   - epoch-millisecond timestamps -> POSIXct (UTC), with the magnitude guard
#     (datetime_auto) used for entities/triples;
#   - JSON-in-TEXT columns -> list-columns via jsonlite::fromJSON(...);
#   - BLOB columns pass through untouched as raw vectors.
# Conversions only apply to columns the manifest declares, so unknown or
# future columns are never touched (forward compatibility).

# Which table's contract does `x` read from? The raw-accessor case is resolved
# by dbplyr::remote_name(); derived queries (filter/select) fall back to a
# FROM-clause inference that only fires for single-table queries. A joined or
# subquery tbl has no single reliable contract and is returned as collected.
ent_infer_base_table <- function(x) {
  tbl <- dbplyr::remote_name(x)
  if (!is.null(tbl)) {
    return(tbl)
  }
  sql <- as.character(dbplyr::sql_render(x))
  if (grepl("(?i)JOIN", sql, perl = TRUE)) {
    return(NULL)
  }
  # Two regexes search for a top-level FROM clause. The first matches quoted
  # identifiers (dbplyr renders these as `"tablename"`). The second is a
  # fallback for bare identifiers and deliberately rejects FROM followed by
  # '(' (subquery) so a derived query's inner table name isn't misidentified
  # as the contract source. Neither regex matches a FROM that appears inside
  # a string literal (a rare corner case — the WHERE clause is after the FROM
  # in RSQLite renders, so the first FROM the regexes see is the real one).
  m <- regexpr("(?i)FROM\\s+[`\"]([^`\"]+)[`\"]", sql, perl = TRUE)
  if (m == -1L) {
    m <- regexpr("(?i)FROM\\s+([A-Za-z_][A-Za-z0-9_]*)(?!\\s*\\()", sql, perl = TRUE)
    if (m == -1L) {
      return(NULL)
    }
  }
  cs <- attr(m, "capture.start")
  cl <- attr(m, "capture.length")
  if (cs[1] < 1) {
    return(NULL)
  }
  substr(sql, cs[1], cs[1] + cl[1] - 1L)
}

# Epoch milliseconds -> POSIXct (UTC). RSQLite returns large timestamps as
# bit64 integer64, which as.POSIXct() cannot handle, so coerce to numeric.
ent_datetime_ms <- function(x) {
  if (inherits(x, "POSIXct")) {
    return(x)
  }
  if (inherits(x, "integer64")) x <- as.numeric(x)
  if (is.character(x)) x <- as.numeric(x)
  as.POSIXct(x / 1000, origin = "1970-01-01", tz = "UTC")
}

# Epoch seconds -> POSIXct (UTC).
ent_datetime_s <- function(x) {
  if (inherits(x, "POSIXct")) {
    return(x)
  }
  if (inherits(x, "integer64")) x <- as.numeric(x)
  if (is.character(x)) x <- as.numeric(x)
  as.POSIXct(x, origin = "1970-01-01", tz = "UTC")
}

# Magnitude-guarded conversion (the migration-0019 rule): values below 1e12
# are epoch seconds, everything else is epoch milliseconds.
ent_datetime_auto <- function(x) {
  if (inherits(x, "POSIXct")) {
    return(x)
  }
  if (inherits(x, "integer64")) x <- as.numeric(x)
  if (is.character(x)) x <- as.numeric(x)
  x <- ifelse(x < 1e12, x, x / 1000)
  as.POSIXct(x, origin = "1970-01-01", tz = "UTC")
}

# Parse ISO-8601 timestamp strings (e.g. "2026-01-15T12:05:00Z") to POSIXct
# (UTC). Base-R equivalent of lubridate::as_datetime; used for ISO-8601
# strings embedded in JSON columns such as
# items.metadata.__entropia_file_metadata.importedAt.
ent_datetime_iso <- function(x) {
  as.POSIXct(x, format = "%Y-%m-%dT%H:%M:%OSZ", tz = "UTC")
}

# Validate that `x` is a timestamp-like vector the datetime helpers can
# convert: numeric, integer64 (as RSQLite returns for large integers), POSIXct
# (passed through unchanged by the internal converters), or an all-numeric
# character vector.
ent_validate_dt_input <- function(x) {
  ok <- is.numeric(x) || inherits(x, "integer64") || inherits(x, "POSIXct")
  if (!ok && is.character(x)) {
    ok <- !anyNA(suppressWarnings(as.numeric(x)))
  }
  if (!ok) {
    ent_abort(
      "entropia_error_invalid_argument",
      c(
        "{.arg x} must be a numeric vector of epoch timestamps.",
        i = "Received {.cls {class(x)}}."
      )
    )
  }
  invisible(x)
}

#' Convert epoch-millisecond timestamps to `POSIXct`
#'
#' Pure helper converting epoch-millisecond timestamps (13-digit integers, as
#' stored in `created_at`/`updated_at` on most EntropIA tables) to `POSIXct`
#' in the UTC timezone. Handles `integer64` vectors as returned by RSQLite.
#'
#' @param x A numeric (or `integer64`) vector of epoch-millisecond timestamps.
#' @return A `POSIXct` vector (UTC).
#' @examples
#' entropia_datetime(1768478460000)
#' @export
entropia_datetime <- function(x) {
  ent_validate_dt_input(x)
  ent_datetime_ms(x)
}

#' Convert epoch-second timestamps to `POSIXct`
#'
#' Pure helper converting epoch-second timestamps (10-digit integers, as used
#' by `_migrations.applied_at`) to `POSIXct` in the UTC timezone.
#'
#' @param x A numeric (or `integer64`) vector of epoch-second timestamps.
#' @return A `POSIXct` vector (UTC).
#' @examples
#' entropia_datetime_s(1768478400)
#' @export
entropia_datetime_s <- function(x) {
  ent_validate_dt_input(x)
  ent_datetime_s(x)
}

#' Convert timestamps to `POSIXct` with a magnitude guard
#'
#' Pure helper for columns whose unit is not guaranteed (currently
#' `entities.created_at` and `triples.created_at`, whose DDL default is epoch
#' seconds but which the app writes in milliseconds). Values below `1e12` are
#' treated as epoch seconds, everything else as epoch milliseconds -- the same
#' guard EntropIA migration 0019 used.
#'
#' @param x A numeric (or `integer64`) vector of timestamps.
#' @return A `POSIXct` vector (UTC).
#' @examples
#' entropia_datetime_auto(1768478400) # seconds
#' entropia_datetime_auto(1768478400000) # milliseconds
#' @export
entropia_datetime_auto <- function(x) {
  ent_validate_dt_input(x)
  ent_datetime_auto(x)
}

# Parse a JSON-in-TEXT column into a list-column. Each cell becomes one element
# (data.frame for arrays of objects, named list for objects, vector for simple
# arrays/scalars). Malformed JSON warns and yields NA rather than failing the
# whole collect -- a tolerant read posture consistent with the schema policy.
ent_parse_json_col <- function(x) {
  if (is.list(x)) {
    return(x)
  } # already parsed (idempotent)
  if (!is.character(x)) {
    return(x)
  }
  lapply(x, function(z) {
    if (length(z) != 1L || is.na(z)) {
      return(NA_character_)
    }
    parsed <- tryCatch(
      jsonlite::fromJSON(z, simplifyVector = TRUE),
      error = function(e) e
    )
    if (inherits(parsed, "condition")) {
      cli::cli_warn(
        "Malformed JSON, returning NA: {ent_sanitize_msg(conditionMessage(parsed))}",
        class = "entropia_warn_malformed_json"
      )
      return(NA_character_)
    }
    parsed
  })
}

# Apply the manifest contract to a collected data.frame, in place by column.
ent_apply_contract <- function(out, columns) {
  for (nm in names(columns)) {
    if (!nm %in% names(out)) next
    contract <- columns[[nm]]$contract
    if (is.null(contract)) next
    out[[nm]] <- switch(contract,
      datetime_ms = ent_datetime_ms(out[[nm]]),
      datetime_s = ent_datetime_s(out[[nm]]),
      datetime_auto = ent_datetime_auto(out[[nm]]),
      json = ent_parse_json_col(out[[nm]]),
      out[[nm]] # int/dbl/enum/blob_f32 need no conversion in v1
    )
  }
  tibble::as_tibble(out)
}

#' Collect and apply the column contract
#'
#' Like [dplyr::collect()] on a lazy table, but additionally applies the
#' package's column contract: epoch-millisecond timestamps become `POSIXct`
#' (UTC), JSON-in-TEXT columns (e.g. `transcriptions.segments`) become
#' list-columns, and BLOB columns stay raw. Columns the manifest does not
#' describe are returned unchanged.
#'
#' The contract is resolved from the table's base table. For a lazy query that
#' is not a simple single-table read (joins, subqueries) the columns are
#' returned as SQLite produced them -- keep filters/selects inside the lazy
#' query for best results.
#'
#' @param x A lazy table, e.g. from [entropia_items()].
#' @param n Maximum number of rows to fetch, passed to [dplyr::collect()].
#' @param ... Additional arguments passed to [dplyr::collect()].
#' @return A [tibble::tibble()] with the column contract applied.
#' @examples
#' con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
#'   package = "entropiaR"
#' ))
#' entropia_collect(entropia_items(con)) # created_at -> POSIXct, metadata -> list-column
#' entropia_disconnect(con)
#' @export
entropia_collect <- function(x, n = Inf, ...) {
  if (!inherits(x, "tbl_sql")) {
    ent_abort(
      "entropia_error_invalid_argument",
      c(
        "{.arg x} must be a lazy {.cls tbl_sql} table.",
        i = paste0(
          "Create one with an accessor such as {.fn entropia_items}, ",
          "then call {.fn entropia_collect} on it."
        )
      )
    )
  }
  out <- dplyr::collect(x, n = n, ...)
  base <- ent_infer_base_table(x)
  if (is.null(base)) {
    return(out)
  }
  mentry <- ent_manifest()$tables[[base]]
  if (is.null(mentry)) {
    return(out)
  }
  ent_apply_contract(out, mentry$columns)
}
