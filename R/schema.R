# Schema introspection and the column contract.
#
# The schema surface has two sources of truth:
#   1. the live database (sqlite_master + PRAGMA table_xinfo) -- what exists;
#   2. inst/schemas/manifest.json -- the shipped column contract for the
#      post-0029 reference schema, tagged with the migration that guarantees
#      each column.
# entropia_schema_info() merges the two so callers see both what the package
# understands and what the database actually has. The compatibility policy
# (Task 6) consumes the same primitives.

# Tables readable by the package: every table in sqlite_master except SQLite
# internals (sqlite_*) and FTS5 shadow tables (the fts_*_config/data/docsize/
# idx/content companions).
ent_tables <- function(con) {
  tabs <- DBI::dbGetQuery(
    con,
    "SELECT name, sql FROM sqlite_master WHERE type = 'table'"
  )
  virtual <- tabs$name[grepl("^CREATE VIRTUAL TABLE", tabs$sql)]
  shadow <- unlist(lapply(virtual, function(v) {
    paste0(v, c("_config", "_data", "_docsize", "_idx", "_content"))
  }), use.names = FALSE)
  keep <- !(startsWith(tabs$name, "sqlite_") | tabs$name %in% shadow)
  sort(tabs$name[keep])
}

# Columns of a table via PRAGMA table_xinfo: regular columns (hidden == 0)
# plus generated columns (hidden >= 3). Errors with
# entropia_error_table_missing when the table does not exist.
ent_columns <- function(con, table) {
  available <- ent_tables(con)
  if (!table %in% available) {
    ent_abort(
      "entropia_error_table_missing",
      c(
        "Table {.val {table}} does not exist in this database.",
        i = "Available tables: {.val {available}}."
      ),
      table = table
    )
  }
  q <- DBI::dbQuoteString(con, table)
  info <- DBI::dbGetQuery(con, paste0("PRAGMA table_xinfo(", q, ")"))
  info <- info[info$hidden == 0 | info$hidden >= 3, , drop = FALSE]
  data.frame(
    name = info$name,
    type = info$type,
    notnull = as.logical(info$notnull),
    pk = as.integer(info$pk),
    hidden = as.integer(info$hidden),
    stringsAsFactors = FALSE
  )
}

# Path to the bundled schema manifest inside the installed package.
ent_manifest_path <- function() {
  system.file("schemas", "manifest.json", package = "entropiaR")
}

# Load the column contract. Returns a nested list (fromJSON with
# simplifyVector = FALSE so names and order are preserved exactly).
ent_manifest <- function() {
  p <- ent_manifest_path()
  if (!nzchar(p)) {
    ent_abort(
      "entropia_error_manifest_missing",
      c(
        "The schema manifest could not be found.",
        i = "Expected it at {.path inst/schemas/manifest.json} in the installed package."
      )
    )
  }
  jsonlite::fromJSON(p, simplifyVector = FALSE)
}

# Does a column with `min_version` (NULL = no migration guarantees it) apply to
# a database at schema version `ver`? Lexicographic comparison is safe because
# migration names are zero-padded fixed-width (e.g. "0029_rag_chunks").
ent_min_version_applies <- function(min_version, ver) {
  if (is.null(min_version) || is.na(min_version)) {
    return(TRUE) # repair/sync tables are expected at any version
  }
  if (is.null(ver) || is.na(ver)) {
    return(NA) # unknown database version -> unknown expectation
  }
  ver >= min_version
}

# Manifest columns absent from the live schema, one row per gap. `expected`
# records whether the database version should already have the column (TRUE),
# should not yet (FALSE), or whether that cannot be determined (NA). This is
# the raw material for the compatibility policy in Task 6.
ent_schema_gaps <- function(con) {
  ent_require_conn(con)
  mf <- ent_manifest()
  ver <- ent_current_version(con)
  live_tables <- ent_tables(con)
  out <- list()
  for (t in names(mf$tables)) {
    if (!t %in% live_tables) next # table absent entirely: handled elsewhere
    mentry <- mf$tables[[t]]
    live_cols <- ent_columns(con, t)$name
    for (c in names(mentry$columns)) {
      if (c %in% live_cols) next
      mc <- mentry$columns[[c]]
      out[[length(out) + 1]] <- data.frame(
        table = t,
        column = c,
        type = mc$type %||% NA_character_,
        required = isTRUE(mc$required),
        min_version = mc$min_version %||% NA_character_,
        current_version = ver %||% NA_character_,
        expected = ent_min_version_applies(mc$min_version %||% NULL, ver),
        stringsAsFactors = FALSE
      )
    }
  }
  if (length(out) == 0) {
    return(tibble::tibble(
      table = character(), column = character(), type = character(),
      required = logical(), min_version = character(),
      current_version = character(), expected = logical()
    ))
  }
  tibble::as_tibble(do.call(rbind, out))
}

#' Schema version of an EntropIA database
#'
#' Returns the authoritative schema version: the lexicographic maximum of the
#' `_migrations` table (e.g. `"0029_rag_chunks"`). `NA_character_` when the
#' database has no `_migrations` table.
#'
#' @param con A connection returned by [entropia_connect()].
#' @return A single string, or `NA_character_`.
#' @export
entropia_schema_version <- function(con) {
  ent_require_conn(con)
  ent_current_version(con)
}

#' Tables, columns and typed contract of an EntropIA database
#'
#' Merges the live schema (from `PRAGMA table_xinfo`) with the shipped column
#' contract (`inst/schemas/manifest.json`). Every readable table gets one row
#' per column. `source` records whether the row came from the manifest contract
#' (`"manifest"`) or only exists in the live database (`"schema"`); columns
#' present in both are reported under the manifest (the contract is the typed
#' surface). `min_version` is the migration that guarantees the column, and
#' `required` marks columns whose absence is a compatibility failure once the
#' database reaches that version.
#'
#' @param con A connection returned by [entropia_connect()].
#' @return A tibble with columns `table`, `column`, `type`, `required`,
#'   `contract`, `min_version` and `source`.
#' @export
entropia_schema_info <- function(con) {
  ent_require_conn(con)
  mf <- ent_manifest()
  rows <- list()
  for (t in ent_tables(con)) {
    live <- ent_columns(con, t)
    mentry <- mf$tables[[t]]
    manifest_cols <- if (is.null(mentry)) character() else names(mentry$columns)
    live_only <- setdiff(live$name, manifest_cols)
    for (c in live_only) {
      i <- match(c, live$name)
      rows[[length(rows) + 1]] <- data.frame(
        table = t, column = c, type = live$type[i],
        required = FALSE, contract = NA_character_,
        min_version = NA_character_, source = "schema",
        stringsAsFactors = FALSE
      )
    }
    if (!is.null(mentry)) {
      for (c in manifest_cols) {
        mc <- mentry$columns[[c]]
        # Column-level min_version overrides the table-level one.
        mv <- mc$min_version %||% mentry$min_version %||% NA_character_
        rows[[length(rows) + 1]] <- data.frame(
          table = t, column = c, type = mc$type %||% NA_character_,
          required = isTRUE(mc$required),
          contract = mc$contract %||% NA_character_,
          min_version = mv, source = "manifest",
          stringsAsFactors = FALSE
        )
      }
    }
  }
  out <- if (length(rows) > 0) {
    do.call(rbind, rows)
  } else {
    data.frame(
      table = character(), column = character(), type = character(),
      required = logical(), contract = character(),
      min_version = character(), source = character(),
      stringsAsFactors = FALSE
    )
  }
  tibble::as_tibble(out)
}
