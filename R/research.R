# Research layer: full-text search (Task 14). The remaining research helpers
# (entity relations, llm_results reconstruction, conversations) land in Task 19
# in this same file.
#
# entropia_search() is the parameter-safe FTS5 surface. It builds a lazy
# tbl_sql over a raw MATCH query -- the user text is escaped with
# DBI::dbQuoteString() into a SQL string literal (see ent_search_sql() in
# R/sql.R), so no user input can ever escape the literal and run injected SQL.

# A single non-empty, non-NA character string.
ent_validate_search_query <- function(query) {
  ok <- is.character(query) && length(query) == 1L && !is.na(query) &&
    nzchar(trimws(query))
  if (!ok) {
    ent_abort(
      "entropia_error_invalid_argument",
      c(
        "{.arg query} must be a single non-empty string.",
        i = "Received {.cls {class(query)}} of length {.val {length(query)}}."
      )
    )
  }
  invisible(query)
}

# A single positive integer (numeric or integer), or NULL for no limit.
ent_validate_search_limit <- function(limit) {
  ok <- is.numeric(limit) && length(limit) == 1L && !is.na(limit) &&
    limit >= 1 && limit == floor(limit) && is.finite(limit)
  if (!ok) {
    ent_abort(
      "entropia_error_invalid_argument",
      c(
        "{.arg limit} must be a single positive integer.",
        i = "Received {.val {limit}}. Pass {.code NULL} to return all matches."
      )
    )
  }
  invisible(as.integer(limit))
}

# The searchable indexes. Mirrors match.arg() semantics (an omitted argument
# arrives whole as c("items", "chunks") and resolves to the first choice) but
# validates manually so an invalid value carries the
# entropia_error_invalid_argument class like the other accessors.
ent_validate_search_index <- function(index) {
  if (identical(index, c("items", "chunks"))) {
    return("items") # the omitted default
  }
  ok <- is.character(index) && length(index) == 1L && !is.na(index) &&
    index %in% c("items", "chunks")
  if (!ok) {
    ent_abort(
      "entropia_error_invalid_argument",
      "{.arg index} must be one of {.val items} or {.val chunks}."
    )
  }
  index
}

# Both tables of an index must exist before building the query. ent_columns()
# raises entropia_error_table_missing (with the available-table list) for a
# missing table, which is the right class for schemas without the FTS layer.
ent_require_search_tables <- function(con, index) {
  if (index == "items") {
    ent_columns(con, "fts_items")
    ent_columns(con, "items")
  } else {
    ent_columns(con, "rag_chunks_fts")
    ent_columns(con, "rag_chunks")
  }
  invisible(TRUE)
}

#' Search the full-text index
#'
#' Parameter-safe FTS5 search over the `items` or `chunks` index. The query is
#' escaped with [DBI::dbQuoteString()] before splicing into `MATCH`, so user
#' input can never break out of the string literal (injection-safe). Results
#' are returned as a lazy [dplyr::tbl()] ordered by BM25 rank (best first);
#' nothing is fetched until you collect.
#'
#' The `items` index is the contentless `fts_items` table, so the join to
#' `items` on `rowid` is mandatory: searching without it would read `NULL` in
#' every declared column. The `chunks` index joins `rag_chunks_fts.chunk_id` to
#' `rag_chunks.id`; the `embedding` BLOB is never selected (BLOB discipline).
#'
#' @param con A connection returned by [entropia_connect()].
#' @param query A single non-empty search string.
#' @param index Which FTS5 index to search: `"items"` (default) or `"chunks"`.
#' @param limit Maximum number of results. `NULL` (the default) returns all
#'   matches.
#' @return A `tbl_sql`. The `items` index returns item rows (via the
#'   `fts_items.rowid = items.rowid` join) plus a `rank` column; the `chunks`
#'   index returns `rag_chunks` rows plus `rank`.
#' @export
entropia_search <- function(con, query, index = c("items", "chunks"), limit = NULL) {
  ent_require_conn(con)
  index <- ent_validate_search_index(index)
  ent_validate_search_query(query)
  if (!is.null(limit)) {
    limit <- ent_validate_search_limit(limit)
  }
  ent_require_search_tables(con, index)
  tbl <- dplyr::tbl(con, ent_search_sql(con, query, index, limit))
  if (index == "chunks") {
    tbl <- dplyr::select(tbl, -dplyr::any_of("embedding"))
  }
  tbl
}
