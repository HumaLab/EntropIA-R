# Core entity accessors (Task 9).
#
# Every accessor returns a lazy tbl_sql over its raw table: no collect(), no
# column narrowing, so dplyr/dbplyr verbs push down to SQLite and the result
# stays composable. The manifest's required columns are verified at accessor
# time so failures are stable and actionable (entropia_error_table_missing /
# entropia_error_column_missing); optional columns -- e.g. the PDF page
# columns parent_asset_id/page_number on assets -- are exposed when the schema
# has them and simply absent otherwise (older databases keep working).

# Required columns of `table` per the manifest contract (required = TRUE).
# Optional columns are deliberately not required so legacy schemas that
# predate them keep working; the required set is the one present in every
# schema variant.
ent_manifest_required <- function(table) {
  mentry <- ent_manifest()$tables[[table]]
  cols <- mentry$columns
  names(cols)[vapply(cols, function(c) isTRUE(c$required), logical(1))]
}

# Open a lazy tbl_sql over `table`, verifying the manifest's required columns
# first. Shared by all entity accessors so the typing surface stays in one
# place and failures are consistent.
ent_tbl <- function(con, table) {
  ent_require_conn(con)
  ent_require_columns(con, table, ent_manifest_required(table))
  dplyr::tbl(con, table)
}

#' Collections (lazy)
#'
#' A lazy [dplyr::tbl()] over the `collections` table. Nothing is fetched at
#' access time: [dplyr::filter()], [dplyr::select()], [dplyr::summarise()] and
#' friends are translated to SQL and run in SQLite when the result is
#' collected.
#'
#' @param con A connection returned by [entropia_connect()].
#' @return A `tbl_sql` on `collections`.
#' @export
entropia_collections <- function(con) {
  ent_tbl(con, "collections")
}

#' Items (lazy)
#'
#' A lazy [dplyr::tbl()] over the `items` table. The `search_text` generated
#' column is included (it is cheap -- stored, not computed on read). JSON in
#' `metadata` stays raw text until `entropia_collect()` applies the column
#' contract.
#'
#' @param con A connection returned by [entropia_connect()].
#' @return A `tbl_sql` on `items`.
#' @export
entropia_items <- function(con) {
  ent_tbl(con, "items")
}

#' Assets (lazy)
#'
#' A lazy [dplyr::tbl()] over the `assets` table. When the schema has them
#' (migration 0024) the PDF page columns `parent_asset_id` and `page_number`
#' are exposed so pages can be joined back to their parent PDF; on older
#' databases the columns are simply absent. No BLOB column is ever selected:
#' `assets` carries none, and the accessor never pulls one even if a future
#' schema adds it.
#'
#' @param con A connection returned by [entropia_connect()].
#' @return A `tbl_sql` on `assets`.
#' @export
entropia_assets <- function(con) {
  ent_tbl(con, "assets")
}
