# Corpus quality diagnostics (Task 17).
#
# Three surfaces, all read-only:
#   - entropia_ocr_coverage()    : assets without an OCR extraction, or with an
#                                  empty one, per collection / item / asset.
#   - entropia_metadata_coverage(): items without metadata, per collection /
#                                   item.
#   - entropia_corpus_quality()  : a combined long-form report over OCR,
#                                  metadata, transcription presence and empty
#                                  texts.
# The first two are lazy tbl_sql so grouping/aggregation stays in SQLite;
# entropia_corpus_quality() materialises a small report (one row per
# metric x group), like entropia_validate() does for findings.

# Validate a single-choice argument against `choices`, carrying the package's
# entropia_error_invalid_argument class (the accessors never throw base match.arg
# errors).
ent_validate_choice <- function(x, choices, arg) {
  ok <- length(x) == 1L && !is.na(x) && x %in% choices
  if (!ok) {
    ent_abort(
      "entropia_error_invalid_argument",
      c(
        "{.arg {arg}} must be one of {.val {choices}}.",
        i = "Received {.val {x}}."
      )
    )
  }
  x
}

# --- OCR coverage ------------------------------------------------------------

# Lazy per-asset OCR base: every asset joined to its 1:1 extraction row and its
# item/collection context, with two derived flags:
#   has_extraction : the asset has an extraction row (0/1, never NA)
#   text_empty     : the extraction text is empty/whitespace-only (0/1, NA when
#                    the asset has no extraction)
# Boolean flags surface as 0/1 integers (SQLite booleans); filter/count against
# them with == 1 / == 0.
ent_ocr_base <- function(con) {
  assets <- dplyr::select(
    ent_tbl(con, "assets"),
    asset_id = "id", item_id = "item_id", asset_type = "type"
  )
  items <- dplyr::select(
    ent_tbl(con, "items"),
    item_id = "id", collection_id = "collection_id"
  )
  colls <- dplyr::select(
    ent_tbl(con, "collections"),
    collection_id = "id", collection_name = "name"
  )
  ext <- dplyr::select(
    ent_tbl(con, "extractions"),
    asset_id = "asset_id", text_content = "text_content"
  )
  assets |>
    dplyr::left_join(items, by = "item_id") |>
    dplyr::left_join(colls, by = "collection_id") |>
    dplyr::left_join(ext, by = "asset_id") |>
    dplyr::mutate(
      has_extraction = !is.na(.data$text_content),
      text_empty = dplyr::if_else(
        is.na(.data$text_content), NA,
        trimws(.data$text_content) == ""
      )
    ) |>
    dplyr::select(-"text_content")
}

# Grouped OCR summary over a per-asset base. `groups` are the column names to
# group by (spliced as symbols). n_empty is COALESCEd so groups whose assets
# have no extraction (all text_empty NULL) report 0, not NA; coverage is the
# fraction of assets with a non-empty extraction, forced real by * 1.0 so
# SQLite does not integer-divide.
ent_ocr_summary <- function(base, groups) {
  base |>
    dplyr::group_by(!!!rlang::syms(groups)) |>
    dplyr::summarise(
      n_assets = dplyr::n(),
      n_with_extraction = sum(.data$has_extraction, na.rm = TRUE),
      n_empty = dplyr::coalesce(sum(.data$text_empty, na.rm = TRUE), 0L),
      .groups = "drop"
    ) |>
    dplyr::mutate(
      n_missing = .data$n_assets - .data$n_with_extraction,
      coverage = (.data$n_with_extraction - .data$n_empty) * 1.0 / .data$n_assets
    )
}

#' OCR coverage (lazy)
#'
#' Reports which assets are missing an OCR extraction, or whose extraction text
#' is empty/whitespace-only, per grouping. Everything stays lazy: the result is
#' a `tbl_sql` whose joins and aggregations run in SQLite when collected.
#'
#' With `by = "asset"` (per-asset detail) each row is one asset with its
#' item/collection context and two flags:
#'
#' - `has_extraction`: the asset has an extraction row.
#' - `text_empty`: the extraction text is empty/whitespace-only (`NA` when the
#'   asset has no extraction).
#'
#' The flags are 0/1 integers (SQLite booleans); filter with `== 1`/`== 0`.
#' With `by = "item"` or `by = "collection"` the result is a grouped summary
#' with `n_assets`, `n_with_extraction`, `n_missing` (no extraction row),
#' `n_empty` (extraction present but empty) and `coverage` (fraction of assets
#' with a non-empty extraction).
#'
#' @param con A connection returned by [entropia_connect()].
#' @param by Grouping: `"collection"` (default), `"item"`, or `"asset"`.
#' @return A `tbl_sql`.
#' @examples
#' con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
#'   package = "entropiaR"
#' ))
#' entropia_collect(entropia_ocr_coverage(con))
#' entropia_collect(entropia_ocr_coverage(con, by = "asset"))
#' entropia_disconnect(con)
#' @export
entropia_ocr_coverage <- function(con, by = "collection") {
  ent_require_conn(con)
  by <- ent_validate_choice(by, c("collection", "item", "asset"), "by")
  base <- ent_ocr_base(con)
  switch(by,
    asset = base,
    item = ent_ocr_summary(base, "item_id"),
    collection = ent_ocr_summary(base, c("collection_id", "collection_name"))
  )
}

# --- Metadata coverage -------------------------------------------------------

# Lazy per-item metadata base: every item joined to its collection, with
# has_metadata (0/1) = metadata present and not empty/whitespace-only. NULL
# metadata short-circuits to 0 (SQLite three-valued logic: FALSE AND NULL).
ent_metadata_base <- function(con) {
  items <- dplyr::select(
    ent_tbl(con, "items"),
    item_id = "id", collection_id = "collection_id", "metadata"
  )
  colls <- dplyr::select(
    ent_tbl(con, "collections"),
    collection_id = "id", collection_name = "name"
  )
  items |>
    dplyr::left_join(colls, by = "collection_id") |>
    dplyr::mutate(
      has_metadata = !is.na(.data$metadata) & trimws(.data$metadata) != ""
    )
}

# Grouped metadata summary over a per-item base (see ent_ocr_summary for the
# grouping and real-division conventions).
ent_metadata_summary <- function(base, groups) {
  base |>
    dplyr::group_by(!!!rlang::syms(groups)) |>
    dplyr::summarise(
      n_items = dplyr::n(),
      n_with_metadata = sum(.data$has_metadata, na.rm = TRUE),
      .groups = "drop"
    ) |>
    dplyr::mutate(
      n_without_metadata = .data$n_items - .data$n_with_metadata,
      coverage = .data$n_with_metadata * 1.0 / .data$n_items
    )
}

#' Metadata coverage (lazy)
#'
#' Reports which items have no metadata (or an empty one), per grouping.
#'
#' With `by = "collection"` (default) each row is one collection with
#' `n_items`, `n_with_metadata`, `n_without_metadata` and `coverage`. With
#' `by = "item"` each row is one item with its collection context and a
#' `has_metadata` flag (0/1 integer). The result is lazy (`tbl_sql`).
#'
#' @param con A connection returned by [entropia_connect()].
#' @param by Grouping: `"collection"` (default) or `"item"`.
#' @return A `tbl_sql`.
#' @examples
#' con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
#'   package = "entropiaR"
#' ))
#' entropia_collect(entropia_metadata_coverage(con))
#' entropia_disconnect(con)
#' @export
entropia_metadata_coverage <- function(con, by = "collection") {
  ent_require_conn(con)
  by <- ent_validate_choice(by, c("collection", "item"), "by")
  base <- ent_metadata_base(con)
  if (identical(by, "item")) {
    return(dplyr::select(base, "item_id", "collection_id", "collection_name", "has_metadata"))
  }
  ent_metadata_summary(base, c("collection_id", "collection_name"))
}

# --- Combined quality report -------------------------------------------------

# Lazy per-asset base with the full text-layer picture: extraction and
# transcription presence plus empty-text flags, derived as one SQL pass. The
# empty-text rule mirrors the app's best-text rule: an asset "has empty text"
# when it has at least one text layer and none of its layers is non-empty.
ent_text_layer_base <- function(con) {
  tabs <- ent_tables(con)
  need <- c("assets", "items", "collections", "extractions", "transcriptions")
  missing <- setdiff(need, tabs)
  if (length(missing) > 0L) {
    ent_abort(
      "entropia_error_table_missing",
      c(
        "The combined quality report needs tables {.val {need}}.",
        i = "Missing here: {.val {missing}}.",
        i = "Available tables: {.val {tabs}}."
      ),
      table = missing[1L]
    )
  }
  assets <- dplyr::select(
    ent_tbl(con, "assets"),
    asset_id = "id", item_id = "item_id", asset_type = "type"
  )
  items <- dplyr::select(
    ent_tbl(con, "items"),
    item_id = "id", collection_id = "collection_id"
  )
  colls <- dplyr::select(
    ent_tbl(con, "collections"),
    collection_id = "id", collection_name = "name"
  )
  ext <- dplyr::select(
    ent_tbl(con, "extractions"),
    asset_id = "asset_id", ext_text = "text_content"
  )
  trx <- dplyr::select(
    ent_tbl(con, "transcriptions"),
    asset_id = "asset_id", trx_text = "text_content"
  )
  assets |>
    dplyr::left_join(items, by = "item_id") |>
    dplyr::left_join(colls, by = "collection_id") |>
    dplyr::left_join(ext, by = "asset_id") |>
    dplyr::left_join(trx, by = "asset_id") |>
    dplyr::mutate(
      has_extraction = !is.na(.data$ext_text),
      text_empty = dplyr::if_else(
        is.na(.data$ext_text), NA,
        trimws(.data$ext_text) == ""
      ),
      has_transcription = !is.na(.data$trx_text),
      trx_empty = dplyr::if_else(
        is.na(.data$trx_text), NA,
        trimws(.data$trx_text) == ""
      ),
      has_text_layer = .data$has_extraction | .data$has_transcription,
      has_nonempty = (.data$has_extraction & !.data$text_empty) |
        (.data$has_transcription & !.data$trx_empty),
      has_empty_text = .data$has_text_layer & !.data$has_nonempty
    ) |>
    dplyr::select(
      "asset_id", "item_id", "collection_id", "collection_name", "asset_type",
      "has_extraction", "text_empty", "has_transcription",
      "has_text_layer", "has_empty_text"
    )
}

#' Combined corpus quality report
#'
#' A compact long-form report over the corpus, one row per `metric` x `group`
#' (group is an asset type for the per-type metrics and a collection name for
#' metadata):
#'
#' - `ocr_coverage`: `n` assets with a non-empty OCR extraction, `total`
#'   assets, per asset type.
#' - `transcription_presence`: `n` assets with a transcription, `total` assets,
#'   per asset type.
#' - `metadata_coverage`: `n` items with metadata, `total` items, per
#'   collection.
#' - `empty_text`: `n` assets whose best text layer is empty/whitespace-only,
#'   `total` assets with at least one text layer, per asset type.
#'
#' `pct` is `n / total`, `NA` when `total` is 0. The report is materialised (it
#' is a small aggregate, like [entropia_validate()] findings) and carries the
#' `entropia_corpus_quality` class.
#'
#' @param con A connection returned by [entropia_connect()].
#' @return A tibble of class `entropia_corpus_quality` with columns `metric`,
#'   `group`, `n`, `total` and `pct`.
#' @examples
#' con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
#'   package = "entropiaR"
#' ))
#' entropia_corpus_quality(con)
#' entropia_disconnect(con)
#' @export
entropia_corpus_quality <- function(con) {
  ent_require_conn(con)
  full <- ent_text_layer_base(con)

  ocr <- dplyr::collect(ent_ocr_summary(full, "asset_type"))
  trx <- dplyr::collect(
    full |>
      dplyr::group_by(!!!rlang::syms("asset_type")) |>
      dplyr::summarise(
        n = sum(.data$has_transcription, na.rm = TRUE),
        total = dplyr::n(),
        .groups = "drop"
      )
  )
  meta <- dplyr::collect(
    ent_metadata_summary(
      ent_metadata_base(con),
      c("collection_id", "collection_name")
    )
  )
  empty <- dplyr::collect(
    full |>
      dplyr::group_by(!!!rlang::syms("asset_type")) |>
      dplyr::summarise(
        n = sum(.data$has_empty_text, na.rm = TRUE),
        total = sum(.data$has_text_layer, na.rm = TRUE),
        .groups = "drop"
      )
  )

  rows <- dplyr::bind_rows(
    tibble::tibble(
      metric = "ocr_coverage",
      group = ocr$asset_type,
      n = ocr$n_with_extraction - ocr$n_empty,
      total = ocr$n_assets
    ),
    tibble::tibble(
      metric = "transcription_presence",
      group = trx$asset_type,
      n = trx$n,
      total = trx$total
    ),
    tibble::tibble(
      metric = "metadata_coverage",
      group = meta$collection_name,
      n = meta$n_with_metadata,
      total = meta$n_items
    ),
    tibble::tibble(
      metric = "empty_text",
      group = empty$asset_type,
      n = empty$n,
      total = empty$total
    )
  )
  rows <- dplyr::mutate(
    rows,
    pct = dplyr::if_else(.data$total == 0, NA_real_, .data$n / .data$total)
  )
  rows <- dplyr::arrange(rows, .data$metric, .data$group)
  class(rows) <- c("entropia_corpus_quality", class(rows))
  rows
}

# --- Orphaned references ----------------------------------------------------

# One conceptual-FK orphan check. `table` holds its own PK in `id` and the FK
# in `fk`, which must reference `ref_table`'s `id`. Rows whose fk is NULL are
# skipped: NULL is the documented "item-level" value for the optional asset_id
# columns, and the required FKs are NOT NULL in the schema, so a NULL never
# indicates a broken reference. The check is a single SQL anti-join pushed down
# to SQLite; only the (usually empty) orphan rows are collected. Returns NULL
# when the tables/columns are absent (schema degrades gracefully) or nothing is
# broken.
ent_orphan_check <- function(con, table, fk, ref_table, kind) {
  if (!ent_has_columns(con, table, c("id", fk))) {
    return(NULL)
  }
  if (!DBI::dbExistsTable(con, ref_table)) {
    return(NULL)
  }
  child <- dplyr::select(
    dplyr::tbl(con, table),
    id = "id", fk = dplyr::all_of(fk)
  )
  parent <- dplyr::select(dplyr::tbl(con, ref_table), pk = "id")
  bad <- dplyr::collect(
    dplyr::anti_join(child, parent, by = c("fk" = "pk")) |>
      dplyr::filter(!is.na(.data$fk))
  )
  if (nrow(bad) == 0L) {
    return(NULL)
  }
  data.frame(
    kind = kind,
    table = table,
    id = as.character(bad$id),
    column = fk,
    ref_table = ref_table,
    message = sprintf(
      "%s %s references %s via %s = %s, which does not exist.",
      table, bad$id, ref_table, fk, bad$fk
    ),
    stringsAsFactors = FALSE
  )
}

# llm_results.target_id points at whichever table target_type names; the three
# known types resolve to the core tables. Rows whose target_type is NULL or
# outside the enum (e.g. the protocol's "unknown") have no determinable target
# and are not checkable, so they are skipped (documented).
ent_orphan_llm <- function(con) {
  if (!ent_has_columns(con, "llm_results", c("id", "target_id", "target_type"))) {
    return(NULL)
  }
  refs <- data.frame(
    type = c("asset", "item", "collection"),
    ref_table = c("assets", "items", "collections"),
    stringsAsFactors = FALSE
  )
  out <- list()
  for (i in seq_len(nrow(refs))) {
    ref <- refs$ref_table[i]
    if (!DBI::dbExistsTable(con, ref)) next
    tp <- refs$type[i] # hoisted: a scalar, so dbplyr escapes it as a literal
    child <- dplyr::tbl(con, "llm_results") |>
      dplyr::filter(.data$target_type == tp) |>
      dplyr::select(id = "id", fk = "target_id") |>
      dplyr::filter(!is.na(.data$fk))
    parent <- dplyr::select(dplyr::tbl(con, ref), pk = "id")
    bad <- dplyr::collect(dplyr::anti_join(child, parent, by = c("fk" = "pk")))
    if (nrow(bad) > 0L) {
      out[[length(out) + 1L]] <- data.frame(
        kind = "llm_target",
        table = "llm_results",
        id = as.character(bad$id),
        column = "target_id",
        ref_table = ref,
        message = sprintf(
          paste0(
            "llm_results %s (target_type = %s) references %s ",
            "via target_id = %s, which does not exist."
          ),
          bad$id, tp, ref, bad$fk
        ),
        stringsAsFactors = FALSE
      )
    }
  }
  if (length(out) == 0L) NULL else do.call(rbind, out)
}

#' Detect orphaned rows (broken conceptual foreign keys)
#'
#' EntropIA declares most relationships only conceptually (many have no
#' physical foreign-key constraint), so a row can silently point at a parent
#' that does not exist. `entropia_orphans()` scans every conceptual foreign key
#' in the schema and reports one row per broken reference:
#'
#' - `items.collection_id` -> `collections.id`
#' - `assets.item_id` -> `items.id` and `assets.parent_asset_id` -> `assets.id`
#' - `extractions`/`transcriptions`/`layouts`.`asset_id` -> `assets.id`
#' - `entities.item_id` -> `items.id` (and `asset_id` -> `assets.id` when set)
#' - `triples.item_id` -> `items.id` (and `asset_id` -> `assets.id` when set)
#' - `notes.item_id` -> `items.id` (and `asset_id` -> `assets.id` when set)
#' - `annotations.asset_id` -> `assets.id`
#' - `llm_results.target_id` -> the table named by `target_type`
#'   (`asset`/`item`/`collection`; `unknown` and NULL targets are not checkable)
#' - `rag_messages.conversation_id` -> `rag_conversations.id`
#' - `rag_chunks.item_id`/`asset_id` -> `items.id`/`assets.id`
#' - `item_topics.item_id`/`topic_id` -> `items.id`/`topics.id`
#'
#' NULL foreign keys are never reported: they are the documented "item-level"
#' value for the optional `asset_id` columns, and the required FKs are `NOT
#' NULL` in the schema. Tables absent from the database are skipped, so minimal
#' and legacy schemas degrade gracefully. The result is materialised (it is a
#' small diagnostic, like [entropia_validate()] findings) and carries the
#' `entropia_orphans` class.
#'
#' @param con A connection returned by [entropia_connect()].
#' @return A tibble of class `entropia_orphans` with columns `kind`, `table`,
#'   `id`, `column`, `ref_table` and `message`, ordered by `kind` then `id`.
#' @examples
#' con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
#'   package = "entropiaR"
#' ))
#' entropia_orphans(con) # zero findings on the example database
#' entropia_disconnect(con)
#' @export
entropia_orphans <- function(con) {
  ent_require_conn(con)
  checks <- list(
    ent_orphan_check(con, "items", "collection_id", "collections", "item_collection"),
    ent_orphan_check(con, "assets", "item_id", "items", "asset_item"),
    ent_orphan_check(con, "assets", "parent_asset_id", "assets", "asset_parent"),
    ent_orphan_check(con, "extractions", "asset_id", "assets", "extraction_asset"),
    ent_orphan_check(con, "transcriptions", "asset_id", "assets", "transcription_asset"),
    ent_orphan_check(con, "layouts", "asset_id", "assets", "layout_asset"),
    ent_orphan_check(con, "entities", "item_id", "items", "entity_item"),
    ent_orphan_check(con, "entities", "asset_id", "assets", "entity_asset"),
    ent_orphan_check(con, "triples", "item_id", "items", "triple_item"),
    ent_orphan_check(con, "triples", "asset_id", "assets", "triple_asset"),
    ent_orphan_check(con, "notes", "item_id", "items", "note_item"),
    ent_orphan_check(con, "notes", "asset_id", "assets", "note_asset"),
    ent_orphan_check(con, "annotations", "asset_id", "assets", "annotation_asset"),
    ent_orphan_check(
      con, "rag_messages", "conversation_id", "rag_conversations",
      "message_conversation"
    ),
    ent_orphan_check(con, "rag_chunks", "item_id", "items", "chunk_item"),
    ent_orphan_check(con, "rag_chunks", "asset_id", "assets", "chunk_asset"),
    ent_orphan_check(con, "item_topics", "item_id", "items", "item_topic_item"),
    ent_orphan_check(con, "item_topics", "topic_id", "topics", "item_topic_topic"),
    ent_orphan_llm(con)
  )
  checks <- Filter(Negate(is.null), checks)
  if (length(checks) == 0L) {
    out <- data.frame(
      kind = character(), table = character(), id = character(),
      column = character(), ref_table = character(), message = character(),
      stringsAsFactors = FALSE
    )
  } else {
    out <- do.call(rbind, checks)
  }
  out <- out[order(out$kind, out$table, out$id), , drop = FALSE]
  rownames(out) <- NULL
  out <- tibble::as_tibble(out)
  class(out) <- c("entropia_orphans", class(out))
  out
}

#' @export
print.entropia_orphans <- function(x, ...) {
  if (nrow(x) == 0L) {
    cli::cli_inform("No orphaned rows detected.")
    return(invisible(x))
  }
  kinds <- unique(x$kind)
  cat(sprintf("Found %d orphaned row(s):\n", nrow(x)))
  for (k in kinds) {
    cat(sprintf("  %-22s %d\n", k, sum(x$kind == k)))
  }
  cat("\n")
  NextMethod("print")
}
