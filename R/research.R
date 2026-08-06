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
#' @examples
#' con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
#'   package = "entropiaR"
#' ))
#' entropia_collect(entropia_search(con, "huelga"))
#' entropia_collect(entropia_search(con, "huelga", index = "chunks", limit = 5))
#' entropia_disconnect(con)
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

# --- Research layer: conversations, relations, reconstruction -----------------
#
# Three research surfaces that sit on top of the raw accessors:
#   - entropia_conversation()     : one RAG conversation, materialised with its
#                                   message chain ordered by sort_index and the
#                                   sources citations parsed.
#   - entropia_entity_relations() : lazy triples with item/collection context.
#   - entropia_reconstruct_analysis(): llm_results joined back to the row they
#                                   analysed (asset/item/collection by
#                                   target_type) with result parsed.
# The first and third are materialised because the caller asks for a specific
# conversation or for heterogeneous target joins that one SQL query cannot
# express; entity_relations stays lazy like the accessors.

# A single non-empty conversation id.
ent_validate_conversation_id <- function(id) {
  ok <- is.character(id) && length(id) == 1L && !is.na(id) && nzchar(id)
  if (!ok) {
    ent_abort(
      "entropia_error_invalid_argument",
      c(
        "{.arg id} must be a single non-empty conversation id.",
        i = "Received {.cls {class(id)}} of length {.val {length(id)}}."
      )
    )
  }
  invisible(id)
}

#' One RAG conversation with its ordered messages
#'
#' Materialises a single retrieval-augmented chat conversation: the
#' `rag_conversations` row plus its `rag_messages`, ordered by `sort_index`.
#' The `sources` citations on assistant messages are parsed from JSON into a
#' list-column (each element a data.frame of `{chunk_id, text, score}` rows);
#' user messages carry `NA`. Timestamps become `POSIXct`.
#'
#' Returns a list of class `entropia_conversation` with two elements:
#'
#' - `conversation`: a one-row tibble (id, title, created_at, updated_at).
#' - `messages`: a tibble with `id`, `sort_index`, `role`, `content`,
#'   `sources`, `model` and `created_at`, ordered by `sort_index`.
#'
#' @param con A connection returned by [entropia_connect()].
#' @param id A single conversation id (a value of `rag_conversations.id`).
#' @return A list of class `entropia_conversation`.
#' @examples
#' con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
#'   package = "entropiaR"
#' ))
#' entropia_conversation(con, "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1")
#' entropia_disconnect(con)
#' @export
entropia_conversation <- function(con, id) {
  ent_require_conn(con)
  ent_validate_conversation_id(id)
  convs <- ent_tbl(con, "rag_conversations")
  conv <- dplyr::collect(dplyr::filter(convs, .data$id == !!id))
  if (nrow(conv) == 0L) {
    ent_abort(
      "entropia_error_not_found",
      c(
        "Conversation {.val {id}} was not found.",
        i = paste0(
          "List conversations with {.fn entropia_rag_conversations} and pass ",
          "one of their {.code id} values."
        )
      ),
      id = id
    )
  }
  conv <- ent_apply_contract(conv, ent_manifest()$tables$rag_conversations$columns)

  msgs <- ent_tbl(con, "rag_messages")
  m <- dplyr::collect(
    dplyr::filter(msgs, .data$conversation_id == !!id) |>
      dplyr::arrange(.data$sort_index)
  )
  m <- ent_apply_contract(m, ent_manifest()$tables$rag_messages$columns)

  out <- list(conversation = conv, messages = m)
  class(out) <- c("entropia_conversation", class(out))
  out
}

#' @export
print.entropia_conversation <- function(x, ...) {
  conv <- x$conversation
  has_title <- nrow(conv) > 0L && "title" %in% names(conv) && !is.na(conv$title[1L])
  title <- if (has_title) conv$title[1L] else conv$id[1L]
  cat(sprintf("EntropIA conversation: %s\n", title))
  if (nrow(conv) > 0L && "created_at" %in% names(conv)) {
    cat(sprintf("  created: %s\n", format(conv$created_at[1L], usetz = TRUE)))
  }
  cat(sprintf("  %d message(s):\n", nrow(x$messages)))
  if (nrow(x$messages) > 0L) {
    msgs <- x$messages
    roles <- if ("role" %in% names(msgs)) msgs$role else rep("?", nrow(msgs))
    contents <- if ("content" %in% names(msgs)) msgs$content else rep("", nrow(msgs))
    idx <- if ("sort_index" %in% names(msgs)) msgs$sort_index else seq_len(nrow(msgs))
    for (i in seq_len(nrow(msgs))) {
      txt <- substr(contents[i], 1L, 60L)
      cat(sprintf("  [%s] %s: %s\n", format(idx[i]), roles[i], txt))
    }
  }
  invisible(x)
}

#' Entity relations (triples with item and collection context)
#'
#' A lazy [dplyr::tbl()] over `triples` joined to the item and collection it
#' came from, so every subject/predicate/object extraction carries its
#' provenance:
#'
#' - `id`, `subject`, `predicate`, `object`: the triple itself.
#' - `item_id`, `item_title`: the owning item and its title.
#' - `collection_id`, `collection_name`: the item's collection.
#' - `asset_id`: the specific asset the triple is scoped to, `NA` for
#'   item-level triples.
#'
#' Everything stays lazy: the joins run in SQLite when the result is collected.
#'
#' `min_confidence` is accepted for API stability with the plan's research
#' layer, but the current schema's `triples` table has no confidence column, so
#' passing a non-`NULL` value errors with guidance rather than silently doing
#' nothing.
#'
#' @param con A connection returned by [entropia_connect()].
#' @param min_confidence Unused in the current schema (triples carry no
#'   confidence column); must be `NULL` (the default).
#' @return A `tbl_sql`.
#' @examples
#' con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
#'   package = "entropiaR"
#' ))
#' entropia_collect(entropia_entity_relations(con))
#' entropia_disconnect(con)
#' @export
entropia_entity_relations <- function(con, min_confidence = NULL) {
  ent_require_conn(con)
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
    ent_abort(
      "entropia_error_invalid_argument",
      c(
        "{.arg min_confidence} cannot be used with the current schema.",
        i = paste0(
          "The {.code triples} table has no confidence column, so relations ",
          "cannot be thresholded. Pass {.val NULL} (the default) to keep all ",
          "triples."
        )
      )
    )
  }
  triples <- dplyr::select(
    ent_tbl(con, "triples"),
    "id", "subject", "predicate", "object", "item_id", "asset_id"
  )
  items <- dplyr::select(
    ent_tbl(con, "items"),
    item_id = "id", item_title = "title", collection_id = "collection_id"
  )
  colls <- dplyr::select(
    ent_tbl(con, "collections"),
    collection_id = "id", collection_name = "name"
  )
  triples |>
    dplyr::left_join(items, by = "item_id") |>
    dplyr::left_join(colls, by = "collection_id")
}

# Resolve one llm_results target row. `type` names the target table (asset ->
# assets, item -> items, collection -> collections); a row whose type is NULL,
# unknown, or whose id does not exist resolves to NULL (unresolvable). The
# looked-up row is typed via entropia_collect so its contract applies.
ent_resolve_llm_target <- function(con, type, id) {
  refs <- c(asset = "assets", item = "items", collection = "collections")
  if (is.na(type) || !type %in% names(refs)) {
    return(NULL)
  }
  tab <- refs[[type]]
  if (!DBI::dbExistsTable(con, tab)) {
    return(NULL)
  }
  row <- dplyr::filter(dplyr::tbl(con, tab), .data$id == !!id)
  out <- entropia_collect(row)
  if (nrow(out) == 0L) NULL else out
}

#' Reconstruct LLM analyses against their targets
#'
#' Joins `llm_results` rows back to the row they analysed. The target table is
#' named per row by `target_type` (`asset`, `item` or `collection`; `unknown`
#' and missing targets have no resolvable row), so this cannot be one SQL join:
#' each row's target is looked up in the table its type names and returned as a
#' `target` list-column (a one-row tibble, or `NULL` when unresolvable). The
#' `result` JSON is parsed into a list-column and timestamps become `POSIXct`.
#'
#' Materialised (one row per `llm_results` row) and ordered deterministically
#' by `id`; the result carries the `entropia_reconstruction` class.
#'
#' @param con A connection returned by [entropia_connect()].
#' @param target Optional single target id (an asset/item/collection id) to
#'   keep. `NULL` (the default) keeps all targets.
#' @param job_type Optional character vector of job types to keep. `NULL` (the
#'   default) keeps all.
#' @return A tibble of class `entropia_reconstruction`.
#' @examples
#' con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
#'   package = "entropiaR"
#' ))
#' entropia_reconstruct_analysis(con)
#' entropia_disconnect(con)
#' @export
entropia_reconstruct_analysis <- function(con, target = NULL, job_type = NULL) {
  ent_require_conn(con)
  if (!is.null(target)) {
    if (!is.character(target) || length(target) != 1L || is.na(target) || !nzchar(target)) {
      ent_abort(
        "entropia_error_invalid_argument",
        c(
          "{.arg target} must be a single non-empty target id.",
          i = paste0(
            "Pass the {.code id} of an asset, item or collection, or {.val NULL} ",
            "(the default) to keep all targets."
          )
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
  lr <- ent_tbl(con, "llm_results", required = ent_manifest_required_gated(con, "llm_results"))
  if (!is.null(target)) lr <- dplyr::filter(lr, .data$target_id == !!target)
  if (!is.null(job_type)) lr <- dplyr::filter(lr, .data$job_type %in% !!job_type)
  rows <- dplyr::collect(lr)
  rows <- dplyr::arrange(rows, .data$id)
  rows <- ent_apply_contract(rows, ent_manifest()$tables$llm_results$columns)
  # Pre-0019 schemas have no target_type column; nothing is resolvable then.
  if (!"target_type" %in% names(rows)) {
    rows$target_type <- NA_character_
  }
  rows$target <- lapply(seq_len(nrow(rows)), function(i) {
    ent_resolve_llm_target(con, rows$target_type[i], rows$target_id[i])
  })
  class(rows) <- c("entropia_reconstruction", class(rows))
  rows
}

#' @export
print.entropia_reconstruction <- function(x, ...) {
  cat(sprintf("Reconstructed LLM analyses: %d row(s)\n", nrow(x)))
  if (nrow(x) > 0L) {
    tt <- x$target_type
    tt[is.na(tt)] <- "<unknown>"
    for (nm in unique(tt)) {
      cat(sprintf("  %-10s %d\n", nm, sum(tt == nm)))
    }
    cat("\n")
  }
  NextMethod("print")
}
