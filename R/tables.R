# Entity accessors (Task 9 core; Task 10 text; Task 12 AI/RAG).
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

# Required columns of `table` that this database version must already have.
# ent_manifest_required() demands every required column regardless of the
# database's version, which is right for tables whose contract columns all
# arrived with the migration that introduced the table. A few accessor tables
# gained required columns later -- llm_results.target_type with migration 0019,
# vec_assets.embedding_model/embedding_contract/dimensions with 0028 -- and
# those must not be demanded from older schemas. Accessors whose contract
# spans migrations use this gated set (the plan's version-specific SQL) so
# legacy databases keep working without the late columns.
ent_manifest_required_gated <- function(con, table) {
  mentry <- ent_manifest()$tables[[table]]
  cols <- mentry$columns
  ver <- ent_current_version(con)
  names(cols)[vapply(cols, function(c) {
    isTRUE(c$required) && isTRUE(ent_min_version_applies(c$min_version %||% NULL, ver))
  }, logical(1))]
}

# Open a lazy tbl_sql over `table`, verifying the manifest's required columns
# first. Shared by all entity accessors so the typing surface stays in one
# place and failures are consistent. `required` defaults to the full required
# set; accessors with version-gated contracts pass ent_manifest_required_gated()
# so legacy schemas are not asked for columns they never had.
ent_tbl <- function(con, table, required = ent_manifest_required(table)) {
  ent_require_conn(con)
  ent_require_columns(con, table, required)
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
#' @examples
#' con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
#'   package = "entropiaR"
#' ))
#' entropia_collections(con) # lazy; nothing fetched until collected
#' entropia_collect(entropia_collections(con))
#' entropia_disconnect(con)
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
#' @examples
#' con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
#'   package = "entropiaR"
#' ))
#' entropia_items(con)
#' entropia_collect(entropia_items(con)) # metadata -> list-column, created_at -> POSIXct
#' entropia_disconnect(con)
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
#' @examples
#' con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
#'   package = "entropiaR"
#' ))
#' entropia_assets(con)
#' entropia_collect(entropia_assets(con))
#' entropia_disconnect(con)
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
#' @examples
#' con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
#'   package = "entropiaR"
#' ))
#' entropia_collect(entropia_extractions(con))
#' entropia_disconnect(con)
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
#' @examples
#' con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
#'   package = "entropiaR"
#' ))
#' entropia_collect(entropia_transcriptions(con)) # segments -> list-column
#' entropia_disconnect(con)
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
#' @examples
#' con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
#'   package = "entropiaR"
#' ))
#' entropia_collect(entropia_layouts(con))
#' entropia_disconnect(con)
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
#' @examples
#' con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
#'   package = "entropiaR"
#' ))
#' entropia_collect(entropia_entities(con)) # soft-deleted rows excluded
#' entropia_collect(entropia_entities(con, include_deleted = TRUE))
#' entropia_collect(entropia_entities(con, min_confidence = 0.9))
#' entropia_disconnect(con)
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
#' @examples
#' con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
#'   package = "entropiaR"
#' ))
#' entropia_collect(entropia_triples(con))
#' entropia_disconnect(con)
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
#' @examples
#' con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
#'   package = "entropiaR"
#' ))
#' entropia_collect(entropia_topics(con))
#' entropia_disconnect(con)
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
#' @examples
#' con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
#'   package = "entropiaR"
#' ))
#' entropia_collect(entropia_item_topics(con))
#' entropia_disconnect(con)
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
#' @examples
#' con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
#'   package = "entropiaR"
#' ))
#' entropia_collect(entropia_notes(con))
#' entropia_disconnect(con)
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
#' @examples
#' con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
#'   package = "entropiaR"
#' ))
#' entropia_collect(entropia_annotations(con))
#' entropia_disconnect(con)
#' @export
entropia_annotations <- function(con) {
  ent_tbl(con, "annotations")
}

#' LLM results (lazy)
#'
#' A lazy [dplyr::tbl()] over the `llm_results` table: rows produced by LLM
#' jobs (summaries, analyses, ...) linked to their target via `target_id` plus
#' `target_type` (`asset`, `item`, `collection` or `unknown`). The `id` is
#' deterministic: `llr-{target_type}-{target_id}-{job_type}`. The `result`
#' column is JSON-in-TEXT, parsed by [entropia_collect()] into a list-column.
#'
#' Two optional filters, both pushed down to SQL:
#'
#' - `target_type`: keep only rows whose target is one of the given types. On
#'   databases that predate migration 0019 the column does not exist and
#'   passing a filter errors with guidance; without a filter the accessor
#'   still reads the table.
#' - `job_type`: keep only rows for one or more job types.
#'
#' @param con A connection returned by [entropia_connect()].
#' @param target_type Optional character vector of target types to keep, or
#'   `NULL` (default) for all.
#' @param job_type Optional character vector of job types to keep, or `NULL`
#'   (default) for all.
#' @return A `tbl_sql` on `llm_results`.
#' @examples
#' con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
#'   package = "entropiaR"
#' ))
#' entropia_collect(entropia_llm_results(con))
#' entropia_collect(entropia_llm_results(con, target_type = "item"))
#' entropia_disconnect(con)
#' @export
entropia_llm_results <- function(con, target_type = NULL, job_type = NULL) {
  ent_require_conn(con)
  if (!is.null(target_type)) {
    if (!is.character(target_type) || anyNA(target_type) || any(!nzchar(target_type))) {
      ent_abort(
        "entropia_error_invalid_argument",
        c(
          "{.arg target_type} must be a character vector of target types.",
          i = "Allowed values: {.val asset}, {.val item}, {.val collection}, {.val unknown}."
        )
      )
    }
    known <- c("asset", "item", "collection", "unknown")
    if (any(!target_type %in% known)) {
      ent_abort(
        "entropia_error_invalid_argument",
        c(
          "Unknown target type {.val {setdiff(target_type, known)}}.",
          i = "Allowed values: {.val asset}, {.val item}, {.val collection}, {.val unknown}."
        )
      )
    }
  }
  if (!is.null(job_type)) {
    if (!is.character(job_type) || anyNA(job_type) || any(!nzchar(job_type))) {
      ent_abort(
        "entropia_error_invalid_argument",
        c(
          "{.arg job_type} must be a character vector of job types.",
          i = "Pass {.val NULL} (the default) to keep all job types."
        )
      )
    }
  }
  tbl <- ent_tbl(con, "llm_results", required = ent_manifest_required_gated(con, "llm_results"))
  if (!is.null(target_type)) {
    if (!ent_has_columns(con, "llm_results", "target_type")) {
      ent_abort(
        "entropia_error_invalid_argument",
        c(
          paste0(
            "This database predates migration 0019 and its {.code llm_results} ",
            "table has no {.code target_type} column."
          ),
          i = paste0(
            "Filter by {.arg job_type}, or open a database at schema version ",
            "{.val 0019_llm_results_target_type} or later."
          )
        )
      )
    }
    tbl <- dplyr::filter(tbl, .data$target_type %in% !!target_type)
  }
  if (!is.null(job_type)) {
    tbl <- dplyr::filter(tbl, .data$job_type %in% !!job_type)
  }
  tbl
}

#' RAG conversations (lazy)
#'
#' A lazy [dplyr::tbl()] over the `rag_conversations` table: one row per
#' retrieval-augmented chat session.
#'
#' @param con A connection returned by [entropia_connect()].
#' @return A `tbl_sql` on `rag_conversations`.
#' @examples
#' con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
#'   package = "entropiaR"
#' ))
#' entropia_collect(entropia_rag_conversations(con))
#' entropia_disconnect(con)
#' @export
entropia_rag_conversations <- function(con) {
  ent_tbl(con, "rag_conversations")
}

#' RAG messages (lazy)
#'
#' A lazy [dplyr::tbl()] over the `rag_messages` table: the ordered messages of
#' a conversation. `role` is `user` or `assistant`; `sort_index` gives the
#' order within a conversation. The `sources` column is JSON-in-TEXT (an array
#' of `{chunk_id, text, score}` citations on assistant messages), parsed by
#' [entropia_collect()] into a list-column.
#'
#' @param con A connection returned by [entropia_connect()].
#' @return A `tbl_sql` on `rag_messages`.
#' @examples
#' con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
#'   package = "entropiaR"
#' ))
#' entropia_collect(entropia_rag_messages(con)) # sources -> list-column
#' entropia_disconnect(con)
#' @export
entropia_rag_messages <- function(con) {
  ent_tbl(con, "rag_messages")
}

#' Asset embedding vectors (lazy)
#'
#' A lazy [dplyr::tbl()] over the `vec_assets` table (one row per embedded
#' asset). The `embedding` BLOB -- a raw little-endian `f32` vector -- is
#' omitted by default so query results stay small; pass `with_vector = TRUE`
#' to select it. The embedding contract columns (`embedding_model`,
#' `embedding_contract`, `dimensions`) arrived with migration 0028 and are
#' simply absent on older databases.
#'
#' @param con A connection returned by [entropia_connect()].
#' @param with_vector Include the `embedding` BLOB column. Default `FALSE`.
#' @return A `tbl_sql` on `vec_assets`.
#' @examples
#' con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
#'   package = "entropiaR"
#' ))
#' entropia_collect(entropia_embeddings(con)) # no embedding BLOB by default
#' entropia_collect(entropia_embeddings(con, with_vector = TRUE))
#' entropia_disconnect(con)
#' @export
entropia_embeddings <- function(con, with_vector = FALSE) {
  ent_require_conn(con)
  if (length(with_vector) != 1L || is.na(with_vector) || !is.logical(with_vector)) {
    ent_abort(
      "entropia_error_invalid_argument",
      "{.arg with_vector} must be a single {.cls logical} (not {.val {with_vector}})."
    )
  }
  tbl <- ent_tbl(con, "vec_assets", required = ent_manifest_required_gated(con, "vec_assets"))
  if (!with_vector) {
    tbl <- dplyr::select(tbl, -dplyr::any_of("embedding"))
  }
  tbl
}

#' RAG chunks (lazy)
#'
#' A lazy [dplyr::tbl()] over the `rag_chunks` table: chunked text with
#' embeddings for retrieval. The chunking contract is exposed as columns
#' (`chunking_contract`, `embedding_model`, `embedding_contract`, `dimensions`).
#' The `embedding` BLOB is omitted by default; pass `with_vector = TRUE` to
#' select it.
#'
#' @param con A connection returned by [entropia_connect()].
#' @param with_vector Include the `embedding` BLOB column. Default `FALSE`.
#' @return A `tbl_sql` on `rag_chunks`.
#' @examples
#' con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
#'   package = "entropiaR"
#' ))
#' entropia_collect(entropia_chunks(con)) # chunking contract columns exposed
#' entropia_collect(entropia_chunks(con, with_vector = TRUE))
#' entropia_disconnect(con)
#' @export
entropia_chunks <- function(con, with_vector = FALSE) {
  ent_require_conn(con)
  if (length(with_vector) != 1L || is.na(with_vector) || !is.logical(with_vector)) {
    ent_abort(
      "entropia_error_invalid_argument",
      "{.arg with_vector} must be a single {.cls logical} (not {.val {with_vector}})."
    )
  }
  tbl <- ent_tbl(con, "rag_chunks", required = ent_manifest_required_gated(con, "rag_chunks"))
  if (!with_vector) {
    tbl <- dplyr::select(tbl, -dplyr::any_of("embedding"))
  }
  tbl
}

#' Items full-text index (lazy, raw)
#'
#' A lazy [dplyr::tbl()] over the contentless FTS5 table `fts_items`. This is
#' an advanced, raw accessor: contentless FTS5 stores no column content, so
#' selecting its columns directly reads `NULL`. To get searchable text, join to
#' [entropia_items()] on rowid (`items i ON i.rowid = fts_items.rowid`) or use
#' `entropia_search()`.
#'
#' @param con A connection returned by [entropia_connect()].
#' @return A `tbl_sql` on `fts_items`.
#' @examples
#' con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
#'   package = "entropiaR"
#' ))
#' # Raw contentless table: columns read NULL; join to items on rowid for text.
#' entropia_collect(entropia_search_index(con))
#' entropia_disconnect(con)
#' @export
entropia_search_index <- function(con) {
  ent_tbl(con, "fts_items")
}
