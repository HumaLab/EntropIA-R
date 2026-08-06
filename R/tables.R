# Entity accessors (Task 9 core; Task 10 text).
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

#' Extractions (lazy)
#'
#' A lazy [dplyr::tbl()] over the `extractions` table. Each row is the OCR text
#' layer of one asset; `id` is deterministic (`ext-{asset_id}`) and `asset_id`
#' is UNIQUE, so the table joins 1:1 to [entropia_assets()]. `text_content`
#' may embed PDF page markers (`![](page=n,bbox=...)`) which the text layer
#' (`entropia_text()`) can strip.
#'
#' @param con A connection returned by [entropia_connect()].
#' @return A `tbl_sql` on `extractions`.
#' @export
entropia_extractions <- function(con) {
  ent_tbl(con, "extractions")
}

#' Transcriptions (lazy)
#'
#' A lazy [dplyr::tbl()] over the `transcriptions` table. Each row is the
#' audio transcription of one asset; `id` is deterministic
#' (`trx-{asset_id}`) and `asset_id` is UNIQUE (1:1 with
#' [entropia_assets()]). The `segments` column is JSON-in-TEXT (array of
#' `{start_ms, end_ms, text}`); it stays raw until [entropia_collect()]
#' applies the column contract.
#'
#' @param con A connection returned by [entropia_connect()].
#' @return A `tbl_sql` on `transcriptions`.
#' @export
entropia_transcriptions <- function(con) {
  ent_tbl(con, "transcriptions")
}

#' Layouts (lazy)
#'
#' A lazy [dplyr::tbl()] over the `layouts` table. Each row is the page-layout
#' analysis of one asset; `id` is deterministic (`lay-{asset_id}`) and
#' `asset_id` is UNIQUE (1:1 with [entropia_assets()]). `regions` and `blocks`
#' are JSON-in-TEXT columns, parsed by [entropia_collect()].
#'
#' @param con A connection returned by [entropia_connect()].
#' @return A `tbl_sql` on `layouts`.
#' @export
entropia_layouts <- function(con) {
  ent_tbl(con, "layouts")
}

#' Entities (lazy)
#'
#' A lazy [dplyr::tbl()] over the `entities` table (named-entity recognition
#' output). Two filters are applied, both pushed down to SQL:
#'
#' - By default rows marked soft-deleted (`source = "manual_deleted"`, the
#'   app's hidden marker) are excluded; pass `include_deleted = TRUE` to keep
#'   them. On schemas that predate the `source` column (migration 0009) there
#'   is no marker to honour and the filter is a no-op.
#' - Set `min_confidence` to keep only entities at or above a confidence
#'   threshold.
#'
#' `created_at` uses the magnitude-guarded `datetime_auto` contract (the app
#' writes epoch milliseconds, the DDL default is seconds); `asset_id` is NULL
#' for item-level entities.
#'
#' @param con A connection returned by [entropia_connect()].
#' @param include_deleted Include soft-deleted entities (`source =
#'   "manual_deleted"`). Default `FALSE`.
#' @param min_confidence Optional numeric threshold in `[0, 1]`; rows with
#'   `confidence < min_confidence` are excluded. `NULL` (default) keeps all
#'   confidence levels.
#' @return A `tbl_sql` on `entities`.
#' @export
entropia_entities <- function(con, include_deleted = FALSE, min_confidence = NULL) {
  ent_require_conn(con)
  if (length(include_deleted) != 1L || is.na(include_deleted) || !is.logical(include_deleted)) {
    ent_abort(
      "entropia_error_invalid_argument",
      "{.arg include_deleted} must be a single {.cls logical} (not {.val {include_deleted}})."
    )
  }
  if (!is.null(min_confidence)) {
    if (length(min_confidence) != 1L || !is.numeric(min_confidence) ||
        !is.finite(min_confidence) || min_confidence < 0 || min_confidence > 1) {
      ent_abort(
        "entropia_error_invalid_argument",
        c(
          "{.arg min_confidence} must be a single number in {.val [0, 1]}.",
          i = "Received {.val {min_confidence}}."
        )
      )
    }
  }
  tbl <- ent_tbl(con, "entities")
  if (!include_deleted && ent_has_columns(con, "entities", "source")) {
    tbl <- dplyr::filter(tbl, is.na(.data$source) | .data$source != "manual_deleted")
  }
  if (!is.null(min_confidence)) {
    tbl <- dplyr::filter(tbl, .data$confidence >= min_confidence)
  }
  tbl
}

#' Triples (lazy)
#'
#' A lazy [dplyr::tbl()] over the `triples` table (subject/predicate/object
#' extractions). `created_at` uses the magnitude-guarded `datetime_auto`
#' contract; `asset_id` is NULL for item-level triples.
#'
#' @param con A connection returned by [entropia_connect()].
#' @return A `tbl_sql` on `triples`.
#' @export
entropia_triples <- function(con) {
  ent_tbl(con, "triples")
}

#' Topics (lazy)
#'
#' A lazy [dplyr::tbl()] over the `topics` table. Topic names are normalised to
#' UPPERCASE by the app (UNIQUE constraint); the accessor returns them exactly
#' as stored and never re-normalises.
#'
#' @param con A connection returned by [entropia_connect()].
#' @return A `tbl_sql` on `topics`.
#' @export
entropia_topics <- function(con) {
  ent_tbl(con, "topics")
}

#' Item-topic links (lazy)
#'
#' A lazy [dplyr::tbl()] over the `item_topics` join table, linking items to
#' topics (one row per `(item_id, topic_id)` pair, UNIQUE in the app schema).
#'
#' @param con A connection returned by [entropia_connect()].
#' @return A `tbl_sql` on `item_topics`.
#' @export
entropia_item_topics <- function(con) {
  ent_tbl(con, "item_topics")
}

#' Notes (lazy)
#'
#' A lazy [dplyr::tbl()] over the `notes` table. Notes are item-level by
#' default; when `asset_id` is present (migration 0014) the note is scoped to
#' a specific asset instead. `asset_id` is NULL for item-level notes.
#'
#' @param con A connection returned by [entropia_connect()].
#' @return A `tbl_sql` on `notes`.
#' @export
entropia_notes <- function(con) {
  ent_tbl(con, "notes")
}

#' Annotations (lazy)
#'
#' A lazy [dplyr::tbl()] over the `annotations` table (drawing/OCR-cleanup
#' marks on a PDF page). `kind` is an enum (`rectangle`, `underline`, `crop`,
#' `erase`, `rotation`); `page` is 1-based and `x`/`y`/`width`/`height` are
#' coordinates in page units.
#'
#' @param con A connection returned by [entropia_connect()].
#' @return A `tbl_sql` on `annotations`.
#' @export
entropia_annotations <- function(con) {
  ent_tbl(con, "annotations")
}
