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

# --- entropia_corpus ---------------------------------------------------------

# Validate the `text` argument of entropia_corpus(): FALSE omits the text
# layer entirely; otherwise it must be a source mode (reuses the entropia_text
# validator, which carries the entropia_error_invalid_argument class).
ent_validate_text_arg <- function(text) {
  if (isFALSE(text)) return(FALSE)
  ent_validate_text_source(text)
}

# Validate a character-vector filter argument (collections/asset_types).
ent_validate_filter <- function(x, arg) {
  if (is.null(x)) return(x)
  if (!is.character(x) || anyNA(x) || any(!nzchar(x))) {
    ent_abort(
      "entropia_error_invalid_argument",
      c(
        "{.arg {arg}} must be a character vector of values, or {.code NULL}.",
        i = "Received {.cls {class(x)}}."
      )
    )
  }
  x
}

# Append the per-asset text layer to a lazy corpus base. `base` must already
# carry an `asset_id` column. The 1:1 extractions/transcriptions joins cannot
# fan out (both UNIQUE on asset_id), so row cardinality is preserved. The
# selection is one SQL expression per source mode -- COALESCE for `auto`, the
# app's FTS rule. Mirrors entropia_text() but keys off `asset_id` (the corpus
# already renamed assets.id) rather than `id`. Marker stripping is NOT applied
# here: corpus text is the raw layer, and entropia_text() is the stripping
# surface.
ent_append_text_layer <- function(base, con, source) {
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
        i = "Pass {.code text = FALSE} to skip the text layer.",
        i = "Available tables: {.val {tabs}}."
      ),
      table = "extractions"
    )
  }
  if (has_ext) {
    e <- dplyr::select(dplyr::tbl(con, "extractions"), "asset_id", text_ext = "text_content")
    base <- dplyr::left_join(base, e, by = "asset_id")
  }
  if (has_trx) {
    t <- dplyr::select(dplyr::tbl(con, "transcriptions"), "asset_id", text_trx = "text_content")
    base <- dplyr::left_join(base, t, by = "asset_id")
  }
  base_cols <- dplyr::tbl_vars(base)
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
  dplyr::select(out, dplyr::all_of(c(setdiff(base_cols, c("text_ext", "text_trx")), "text")))
}

#' Corpus (lazy)
#'
#' The workhorse research query: a lazy join of `items`, `collections` and
#' `assets`, one row per asset, with an optional per-asset `text` column.
#' Nothing is fetched at access time; every join and filter is pushed down to
#' SQLite, and the result stays composable with [dplyr::filter()],
#' [dplyr::select()] and friends.
#'
#' Column names are unambiguous across the three joined tables (e.g. `item_id`,
#' `asset_id`, `collection_name`, `item_created_at`, `asset_created_at`), so
#' there are no name collisions. `metadata` is the raw JSON text of
#' `items.metadata`; use [entropia_metadata()] for the parsed form. Because the
#' query spans several tables, collecting it applies no column contract --
#' timestamps stay raw integers and `metadata` stays text (see
#' [entropia_collect()]).
#'
#' The `text` column is the asset's best text layer per `source`: `"auto"`
#' (default) uses the extraction text when present, otherwise the
#' transcription -- the app's FTS rule, assembled as one SQL `COALESCE`
#' expression. Markers are NOT stripped (use [entropia_text()] for stripped
#' text). Pass `text = FALSE` to omit the text layer entirely.
#'
#' @param con A connection returned by [entropia_connect()].
#' @param collections Optional character vector of collection names to keep
#'   (matches `collections.name`). `NULL` (default) keeps all collections.
#' @param asset_types Optional character vector of asset types to keep
#'   (matches `assets.type`, e.g. `image`, `pdf`, `audio`). `NULL` (default)
#'   keeps all.
#' @param text The text layer to append: `"auto"` (default), `"extraction"`,
#'   `"transcription"`, or `FALSE` to omit the `text` column.
#' @param page_assets When `TRUE` (default) every asset is kept; when `FALSE`
#'   PDF page assets (rows with a `parent_asset_id`) are excluded. A no-op on
#'   schemas without the page columns (migration 0024).
#' @param include_deleted Reserved. The corpus tables carry no soft-delete
#'   marker in the reference schema, so the flag currently has no effect; it is
#'   validated and kept for API symmetry with [entropia_entities()] and for
#'   forward compatibility with schemas that introduce one.
#' @return A `tbl_sql` with one row per asset and prefixed, non-colliding
#'   columns from `items`, `collections` and `assets`, plus `text` unless
#'   `text = FALSE`.
#' @export
entropia_corpus <- function(con, collections = NULL, asset_types = NULL,
                            text = "auto", page_assets = TRUE, include_deleted = FALSE) {
  ent_require_conn(con)
  text <- ent_validate_text_arg(text)
  collections <- ent_validate_filter(collections, "collections")
  asset_types <- ent_validate_filter(asset_types, "asset_types")
  page_assets <- ent_validate_text_flag(page_assets, "page_assets")
  include_deleted <- ent_validate_text_flag(include_deleted, "include_deleted")

  items <- dplyr::select(
    ent_tbl(con, "items"),
    item_id = "id",
    item_title = "title",
    collection_id = "collection_id",
    "metadata",
    item_created_at = "created_at",
    item_updated_at = "updated_at"
  )
  colls <- dplyr::select(
    ent_tbl(con, "collections"),
    collection_id = "id",
    collection_name = "name",
    collection_description = "description",
    collection_created_at = "created_at",
    collection_updated_at = "updated_at"
  )
  assets <- dplyr::select(
    ent_tbl(con, "assets"),
    asset_id = "id",
    "item_id",
    asset_path = "path",
    asset_type = "type",
    asset_size = "size",
    asset_created_at = "created_at",
    asset_sort_index = "sort_index",
    dplyr::any_of(c("parent_asset_id", "page_number"))
  )

  out <- items |>
    dplyr::left_join(colls, by = "collection_id") |>
    dplyr::left_join(assets, by = "item_id")

  if (!isFALSE(text)) {
    out <- ent_append_text_layer(out, con, text)
  }

  if (!is.null(collections)) {
    out <- dplyr::filter(out, .data$collection_name %in% !!collections)
  }
  if (!is.null(asset_types)) {
    out <- dplyr::filter(out, .data$asset_type %in% !!asset_types)
  }
  if (!page_assets && ent_has_columns(con, "assets", "parent_asset_id")) {
    # PDF page assets are the rows with a non-NULL parent_asset_id.
    out <- dplyr::filter(out, is.na(.data$parent_asset_id))
  }
  out
}

# --- entropia_metadata -------------------------------------------------------

# Resolve the base items query for entropia_metadata():
#   NULL          -> every item in the `items` table
#   character     -> items whose id is in the vector
#   lazy tbl_sql  -> used as-is (must carry `id` and `metadata` columns)
ent_resolve_item_base <- function(con, items) {
  if (is.null(items)) {
    return(ent_tbl(con, "items"))
  }
  if (inherits(items, "tbl_sql")) {
    cols <- dplyr::tbl_vars(items)
    missing <- setdiff(c("id", "metadata"), cols)
    if (length(missing) > 0L) {
      ent_abort(
        "entropia_error_invalid_argument",
        c(
          "{.arg items} must be a lazy table with {.code id} and {.code metadata} columns.",
          i = "Missing column(s): {.val {missing}}."
        )
      )
    }
    return(items)
  }
  if (is.character(items)) {
    if (anyNA(items) || any(!nzchar(items))) {
      ent_abort(
        "entropia_error_invalid_argument",
        "{.arg items} must not contain {.code NA} or empty strings."
      )
    }
    return(dplyr::filter(ent_tbl(con, "items"), .data$id %in% !!items))
  }
  ent_abort(
    "entropia_error_invalid_argument",
    c(
      paste0(
        "{.arg items} must be {.code NULL}, a character vector of item ids, ",
        "or a lazy {.cls tbl_sql}."
      ),
      i = "Received {.cls {class(items)}}."
    )
  )
}

#' Item metadata (parsed)
#'
#' Reads `items.metadata` -- JSON-in-TEXT on every item -- into tidy rows: one
#' row per item (in the order returned by the base query) with `item_id`, the
#' parsed `__entropia_file_metadata` fields `original_name`, `original_path`
#' and `imported_at` (ISO-8601, as `POSIXct` in UTC), and one list-column per
#' remaining top-level metadata key. Items without metadata get one row with
#' `NA` in the parsed fields and `NULL` in the list-columns.
#'
#' Unlike the lazy accessors this function materialises: parsing JSON to
#' list-columns is an R-side step. `parse = FALSE` returns the raw
#' `metadata` text alongside `item_id` instead.
#'
#' @param con A connection returned by [entropia_connect()].
#' @param items `NULL` for all items, a character vector of item ids to keep,
#'   or a lazy table of items (must have `id` and `metadata` columns). Default
#'   `NULL`.
#' @param parse When `TRUE` (default) parse `metadata` into the tidy field
#'   columns; when `FALSE` return the raw `metadata` text column.
#' @return A [tibble::tibble()] with one row per item.
#' @export
entropia_metadata <- function(con, items = NULL, parse = TRUE) {
  ent_require_conn(con)
  if (length(parse) != 1L || is.na(parse) || !is.logical(parse)) {
    ent_abort(
      "entropia_error_invalid_argument",
      "{.arg parse} must be a single {.cls logical} (not {.val {parse}})."
    )
  }
  base <- ent_resolve_item_base(con, items)
  rows <- dplyr::collect(dplyr::select(base, "id", "metadata"))
  out <- tibble::tibble(item_id = rows$id)
  if (!parse) {
    out$metadata <- rows$metadata
    return(out)
  }

  parsed <- lapply(rows$metadata, function(z) {
    if (length(z) != 1L || is.na(z)) return(list())
    p <- tryCatch(jsonlite::fromJSON(z, simplifyVector = TRUE), error = function(e) e)
    if (inherits(p, "condition")) {
      warning(
        sprintf("Malformed JSON in items.metadata, returning NA: %s", conditionMessage(p)),
        call. = FALSE
      )
      return(list())
    }
    p
  })
  fm <- lapply(parsed, function(p) p[["__entropia_file_metadata"]])

  out$original_name <- vapply(
    fm,
    function(x) {
      if (is.null(x[["original_name"]])) {
        NA_character_
      } else {
        as.character(x[["original_name"]])
      }
    },
    character(1)
  )
  out$original_path <- vapply(
    fm,
    function(x) {
      if (is.null(x[["original_path"]])) {
        NA_character_
      } else {
        as.character(x[["original_path"]])
      }
    },
    character(1)
  )
  iso <- vapply(
    fm,
    function(x) if (is.null(x[["importedAt"]])) NA_character_ else as.character(x[["importedAt"]]),
    character(1)
  )
  # suppressWarnings: a malformed importedAt is not a reason to fail the parse;
  # it yields NA (the raw value remains reachable via parse = FALSE).
  out$imported_at <- suppressWarnings(ent_datetime_iso(iso))

  keys <- unique(unlist(lapply(parsed, function(p) setdiff(names(p), "__entropia_file_metadata"))))
  for (k in keys) {
    out[[k]] <- lapply(seq_along(parsed), function(i) {
      p <- parsed[[i]]
      if (is.null(p[[k]])) NULL else p[[k]]
    })
  }
  out
}
