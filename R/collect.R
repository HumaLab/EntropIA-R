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

# Trace only proven column references through dbplyr's lazy query tree.
# SQL sources, joins, and unknown node/selection shapes deliberately lose
# automatic contracts. In particular, an expression's output name is not
# evidence of its type, even when it reuses a manifest column name.
ent_infer_contract <- function(x) {
  walk <- function(q) {
    if (!is.list(q)) {
      return(character())
    }
    if (inherits(q, "lazy_base_query")) {
      # dbplyr >= 2.5 wraps table paths (dbplyr_table_path) and renders idents
      # with backticks; normalize to the bare table name for manifest lookup.
      src <- gsub("`", "", as.character(q$x), fixed = TRUE)
      if (length(src) != 1L || is.na(src) || !nzchar(src) ||
        startsWith(src, "(")) {
        return(character())
      }
      cols <- ent_manifest()$tables[[src]]$columns
      if (is.null(cols) || !is.character(q$vars)) {
        return(character())
      }
      out <- vapply(cols, function(z) {
        if (is.null(z$contract)) "raw" else z$contract
      }, character(1))
      return(out[intersect(names(out), q$vars)])
    }
    if (!inherits(q, "lazy_select_query")) {
      return(character())
    }
    input <- walk(q$x)
    sel <- q$select
    if (!is.list(sel) || !is.character(sel$name) ||
      !is.list(sel$expr) || length(sel$name) != length(sel$expr) ||
      anyNA(sel$name) || anyDuplicated(sel$name)) {
      return(character())
    }
    out <- character()
    for (i in seq_along(sel$name)) {
      expr <- sel$expr[[i]]
      if (rlang::is_quosure(expr)) expr <- rlang::quo_get_expr(expr)
      nm <- if (inherits(expr, "name")) {
        as.character(expr)
      } else if (rlang::is_symbol(expr)) {
        rlang::as_string(expr)
      } else if (is.character(expr) && length(expr) == 1L && !is.na(expr)) {
        expr
      } else {
        NA_character_
      }
      if (!is.na(nm) && nm %in% names(input)) out[sel$name[[i]]] <- input[[nm]]
    }
    out
  }
  walk(x$lazy_query)
}

ent_validate_collect_schema <- function(schema, vars) {
  if (is.null(schema)) {
    return(NULL)
  }
  if (!is.character(schema) || is.null(names(schema)) || anyNA(schema) ||
    anyNA(names(schema)) || any(!nzchar(names(schema))) ||
    anyDuplicated(names(schema)) ||
    any(!schema %in% c("datetime_ms", "datetime_s", "datetime_auto", "json", "raw")) ||
    any(!names(schema) %in% vars)) {
    ent_abort(
      "entropia_error_invalid_argument",
      paste(
        "{.arg schema} must be a uniquely named character vector mapping",
        "existing output columns to datetime_ms, datetime_s, datetime_auto,",
        "json, or raw."
      )
    )
  }
  schema
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
  # Convert to numeric. integer64 values (as returned by RSQLite for large
  # timestamps) can only represent integers up to 2^53 exactly; todays epoch
  # milliseconds (1.7e12) are well below that limit, and the threshold 1e12
  # for epoch seconds is even smaller, so no precision is lost in practice.
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
#' Automatic contracts follow only proven untouched column references and
#' rename aliases through supported dbplyr query nodes. Transformed expressions,
#' joins, raw SQL and unknown query structures remain untyped. Explicit schema
#' entries override inference for those columns; `"raw"` disables conversion.
#'
#' @param x A lazy table, e.g. from [entropia_items()].
#' @param n Maximum number of rows to fetch, passed to [dplyr::collect()].
#' @param ... Additional arguments passed to [dplyr::collect()].
#' @param schema Optional named character vector mapping output columns to
#'   `datetime_ms`, `datetime_s`, `datetime_auto`, `json`, or `raw`.
#' @return A [tibble::tibble()] with the column contract applied.
#' @examples
#' con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
#'   package = "entropiaR"
#' ))
#' entropia_collect(entropia_items(con)) # created_at -> POSIXct, metadata -> list-column
#' entropia_disconnect(con)
#' @export
entropia_collect <- function(x, n = Inf, ..., schema = NULL) {
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
  schema <- ent_validate_collect_schema(schema, dplyr::tbl_vars(x))
  contract <- ent_infer_contract(x)
  contract[names(schema)] <- schema
  out <- dplyr::collect(x, n = n, ...)
  ent_apply_contract(out, lapply(contract, function(z) list(contract = z)))
}
