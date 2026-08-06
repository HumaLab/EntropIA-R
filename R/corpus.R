# Domain layer: per-asset text (Task 15). entropia_corpus() and
# entropia_metadata() land here in Task 16.
#
# entropia_text() is the per-asset best-text surface. It joins every asset to
# its 1:1 extraction and transcription rows (both UNIQUE on asset_id) and
# selects a `text` column per `source`:
#   "extraction"    : extractions.text_content
#   "transcription" : transcriptions.text_content
#   "auto"          : COALESCE(extraction, transcription) (the app's FTS rule)
# The whole selection is one SQL expression over the joins, so there are no
# R-side per-row loops and the result stays lazy. OCR page markers
# (![](page=n,bbox=[...])) are stripped in SQL via a recursive CTE (see
# ent_strip_markers_sql() in R/sql.R), keeping the result composable with
# dplyr. Assets with neither layer get NA text but are still returned.

# Validate the text source argument. The default `"auto"` arrives as a single
# string (not a match.arg-style choice vector), so validation is manual to
# carry the entropia_error_invalid_argument class like the other accessors.
ent_validate_text_source <- function(source) {
  ok <- is.character(source) && length(source) == 1L && !is.na(source) &&
    source %in% c("extraction", "transcription", "auto")
  if (!ok) {
    ent_abort(
      "entropia_error_invalid_argument",
      c(
        "{.arg source} must be one of {.val extraction}, {.val transcription} or {.val auto}.",
        i = "Received {.val {source}}."
      )
    )
  }
  source
}

# A single non-NA logical flag (strip_markers).
ent_validate_text_flag <- function(x, arg) {
  ok <- length(x) == 1L && !is.na(x) && is.logical(x)
  if (!ok) {
    ent_abort(
      "entropia_error_invalid_argument",
      "{.arg {arg}} must be a single {.cls logical} (not {.val {x}})."
    )
  }
  x
}

# Resolve the base assets query for entropia_text():
#   NULL          -> every asset in the `assets` table
#   character     -> assets whose id is in the vector
#   lazy tbl_sql  -> used as-is (must carry an `id` column holding asset ids)
ent_resolve_text_base <- function(con, assets) {
  if (is.null(assets)) {
    return(ent_tbl(con, "assets"))
  }
  if (inherits(assets, "tbl_sql")) {
    cols <- dplyr::tbl_vars(assets)
    if (!"id" %in% cols) {
      ent_abort(
        "entropia_error_invalid_argument",
        c(
          "{.arg assets} must be a lazy table with an {.code id} column (asset ids).",
          i = "Its columns are: {.val {cols}}."
        )
      )
    }
    return(assets)
  }
  if (is.character(assets)) {
    if (anyNA(assets) || any(!nzchar(assets))) {
      ent_abort(
        "entropia_error_invalid_argument",
        "{.arg assets} must not contain {.code NA} or empty strings."
      )
    }
    return(dplyr::filter(ent_tbl(con, "assets"), .data$id %in% !!assets))
  }
  ent_abort(
    "entropia_error_invalid_argument",
    c(
      paste0(
        "{.arg assets} must be {.code NULL}, a character vector of asset ids, ",
        "or a lazy {.cls tbl_sql}."
      ),
      i = "Received {.cls {class(assets)}}."
    )
  )
}

#' Per-asset best text (lazy)
#'
#' Returns one row per asset with a `text` column holding the asset's best
#' available text layer:
#'
#' - `source = "extraction"`: the OCR extraction text
#'   (`extractions.text_content`).
#' - `source = "transcription"`: the audio transcription text
#'   (`transcriptions.text_content`).
#' - `source = "auto"` (default): the extraction text when the asset has one,
#'   otherwise the transcription text -- the same rule the app uses to build
#'   its search index.
#'
#' The selection is assembled in SQL (a single `COALESCE` expression over the
#' 1:1 extractions/transcriptions joins), so nothing is fetched until you
#' collect and there are no per-row R loops. Assets with neither layer get `NA`
#' text; they are still returned (left joins, one row per asset). The returned
#' columns are the input asset columns plus `text`.
#'
#' Extraction text may embed OCR page markers of the form `![](page=n,bbox=[...])`.
#' With `strip_markers = TRUE` (default) they are removed in SQL via a
#' recursive query, so the result stays lazy and composable with
#' [dplyr::filter()] / [dplyr::select()] / friends. The marker itself is
#' removed exactly; surrounding whitespace is preserved.
#'
#' @param con A connection returned by [entropia_connect()].
#' @param assets `NULL` for all assets, a character vector of asset ids to
#'   keep, or a lazy table of assets (must have an `id` column). Default
#'   `NULL`.
#' @param source Which text layer to use: `"auto"` (default), `"extraction"`,
#'   or `"transcription"`.
#' @param strip_markers Remove OCR page markers (`![](page=n,bbox=[...])`) from
#'   the text. Default `TRUE`.
#' @return A `tbl_sql` with the input asset columns plus `text`.
#' @export
entropia_text <- function(con, assets = NULL, source = "auto", strip_markers = TRUE) {
  ent_require_conn(con)
  source <- ent_validate_text_source(source)
  strip_markers <- ent_validate_text_flag(strip_markers, "strip_markers")
  base <- ent_resolve_text_base(con, assets)
  base_cols <- dplyr::tbl_vars(base)

  reserved <- intersect(c("text", "text_ext", "text_trx"), base_cols)
  if (length(reserved) > 0L) {
    ent_abort(
      "entropia_error_invalid_argument",
      c(
        "{.arg assets} already has column(s) reserved by {.fn entropia_text}: {.val {reserved}}.",
        i = "Drop or rename them before calling {.fn entropia_text}."
      )
    )
  }

  tabs <- ent_tables(con)
  has_ext <- "extractions" %in% tabs
  has_trx <- "transcriptions" %in% tabs
  if (source == "extraction" && !has_ext) {
    ent_abort(
      "entropia_error_table_missing",
      c(
        "This database has no {.code extractions} table.",
        i = "Available tables: {.val {tabs}}."
      ),
      table = "extractions"
    )
  }
  if (source == "transcription" && !has_trx) {
    ent_abort(
      "entropia_error_table_missing",
      c(
        "This database has no {.code transcriptions} table.",
        i = "Available tables: {.val {tabs}}."
      ),
      table = "transcriptions"
    )
  }
  if (source == "auto" && !has_ext && !has_trx) {
    ent_abort(
      "entropia_error_table_missing",
      c(
        "This database has neither {.code extractions} nor {.code transcriptions}.",
        i = "Available tables: {.val {tabs}}."
      ),
      table = "extractions"
    )
  }

  if (has_ext) {
    e <- dplyr::select(dplyr::tbl(con, "extractions"), "asset_id", "text_ext" = "text_content")
    base <- dplyr::left_join(base, e, by = c("id" = "asset_id"))
  }
  if (has_trx) {
    t <- dplyr::select(dplyr::tbl(con, "transcriptions"), "asset_id", "text_trx" = "text_content")
    base <- dplyr::left_join(base, t, by = c("id" = "asset_id"))
  }

  out <- switch(source,
    extraction = dplyr::mutate(base, text = .data$text_ext),
    transcription = dplyr::mutate(base, text = .data$text_trx),
    auto = {
      if (has_ext && has_trx) {
        dplyr::mutate(base, text = dplyr::coalesce(.data$text_ext, .data$text_trx))
      } else if (has_ext) {
        dplyr::mutate(base, text = .data$text_ext)
      } else {
        dplyr::mutate(base, text = .data$text_trx)
      }
    }
  )
  out <- dplyr::select(out, dplyr::all_of(c(base_cols, "text")))

  if (strip_markers) {
    cols <- dplyr::tbl_vars(out)
    sql <- ent_strip_markers_sql(cols, as.character(dbplyr::sql_render(out)))
    out <- dplyr::tbl(con, dbplyr::sql(sql))
  }
  out
}
