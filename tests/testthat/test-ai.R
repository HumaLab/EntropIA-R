# Tests for Task 12 (AI/RAG accessors).
#
# entropia_llm_results() filters by target_type/job_type (both pushed down to
# SQL; target_type is version-gated -- the column arrives with migration 0019,
# so legacy-pre0019 databases read without it and refuse the filter with
# guidance). entropia_embeddings()/entropia_chunks() hide the embedding BLOB
# by default and expose it only via with_vector = TRUE. entropia_search_index()
# exposes the raw contentless FTS5 table (columns read NULL without a rowid
# join -- the documented contract). All fixtures come from ent_fixture() (temp
# copies); never data-test/.

# Deterministic fixture ids (mirror data-raw/make_fixtures.R).
AI_ITEM_1 <- "22222222-2222-4222-8222-222222222221"
AI_ASSET_PDF <- "33333333-3333-4333-8333-333333333331"
AI_CHUNK_1 <- "ragchk-0000000000000000000000000000000000000000000000000000000000000001"

with_ai_con <- function(name, f) {
  con <- ent_connect_fixture(name)
  on.exit(try(entropia_disconnect(con), silent = TRUE), add = TRUE)
  f(con)
}

# --- laziness ---------------------------------------------------------------

test_that("AI/RAG accessors are lazy tbl_sql over their raw table", {
  with_ai_con("full", function(con) {
    for (t in list(
      entropia_llm_results(con),
      entropia_rag_conversations(con),
      entropia_rag_messages(con),
      entropia_embeddings(con),
      entropia_chunks(con),
      entropia_search_index(con)
    )) {
      expect_s3_class(t, "tbl_sql")
      expect_false(inherits(t, "data.frame"))
      expect_true(is.na(nrow(t)))
    }
    expect_match(dbplyr::sql_render(entropia_llm_results(con)), "llm_results")
    expect_match(dbplyr::sql_render(entropia_rag_conversations(con)), "rag_conversations")
    expect_match(dbplyr::sql_render(entropia_rag_messages(con)), "rag_messages")
    expect_match(dbplyr::sql_render(entropia_embeddings(con)), "vec_assets")
    expect_match(dbplyr::sql_render(entropia_chunks(con)), "rag_chunks")
    expect_match(dbplyr::sql_render(entropia_search_index(con)), "fts_items")
  })
})

test_that("AI/RAG accessor row counts match the full fixture", {
  with_ai_con("full", function(con) {
    expect_equal(nrow(dplyr::collect(entropia_llm_results(con))), 1L)
    expect_equal(nrow(dplyr::collect(entropia_rag_conversations(con))), 1L)
    expect_equal(nrow(dplyr::collect(entropia_rag_messages(con))), 2L)
    expect_equal(nrow(dplyr::collect(entropia_embeddings(con))), 1L)
    expect_equal(nrow(dplyr::collect(entropia_chunks(con))), 1L)
    expect_equal(nrow(dplyr::collect(entropia_search_index(con))), 3L) # one per item
  })
})

test_that("AI/RAG accessor columns match the manifest contract", {
  with_ai_con("full", function(con) {
    mf <- ent_manifest()
    for (t in c("llm_results", "rag_conversations", "rag_messages")) {
      got <- as.vector(dplyr::tbl_vars(ent_tbl(con, t)))
      want <- names(mf$tables[[t]]$columns)
      expect_identical(got, want, info = t)
    }
    # fts_items manifests its declared columns even though content is NULL.
    expect_identical(
      as.vector(dplyr::tbl_vars(entropia_search_index(con))),
      names(mf$tables$fts_items$columns)
    )
    # with_vector = TRUE selects the full contract, including the BLOB.
    expect_identical(
      as.vector(dplyr::tbl_vars(entropia_embeddings(con, with_vector = TRUE))),
      names(mf$tables$vec_assets$columns)
    )
    expect_identical(
      as.vector(dplyr::tbl_vars(entropia_chunks(con, with_vector = TRUE))),
      names(mf$tables$rag_chunks$columns)
    )
  })
})

# --- llm_results --------------------------------------------------------------

test_that("llm_results exposes the deterministic id and target/job surface", {
  with_ai_con("full", function(con) {
    out <- entropia_collect(entropia_llm_results(con))
    expect_equal(nrow(out), 1L)
    # ids follow the llr-<target_type>-<target_id>-<job_type> convention
    expect_identical(out$id, paste0("llr-item-", AI_ITEM_1, "-summary"))
    expect_identical(out$target_id, AI_ITEM_1)
    expect_identical(out$target_type, "item")
    expect_identical(out$job_type, "summary")
    # result is JSON-in-TEXT -> list-column via entropia_collect
    expect_true(is.list(out$result))
    expect_identical(out$result[[1]]$summary, "Documento sobre la huelga general.")
    expect_identical(out$result[[1]]$tags, c("historia", "movimiento-obrero"))
    # created_at (epoch ms) becomes POSIXct
    expect_s3_class(out$created_at, "POSIXct")
  })
})

test_that("llm_results filters push down to SQL and compose", {
  with_ai_con("full", function(con) {
    sql <- dbplyr::sql_render(entropia_llm_results(con, target_type = "item"))
    expect_match(sql, "target_type")
    expect_match(sql, "IN")
    expect_match(
      dbplyr::sql_render(entropia_llm_results(con, job_type = "summary")),
      "job_type"
    )

    expect_equal(nrow(dplyr::collect(entropia_llm_results(con, target_type = "item"))), 1L)
    expect_equal(nrow(dplyr::collect(entropia_llm_results(con, target_type = "asset"))), 0L)
    # a vector of types is a subset, not an exact match
    expect_equal(
      nrow(dplyr::collect(entropia_llm_results(con, target_type = c("item", "asset")))),
      1L
    )
    expect_equal(nrow(dplyr::collect(entropia_llm_results(con, job_type = "summary"))), 1L)
    expect_equal(nrow(dplyr::collect(entropia_llm_results(con, job_type = "nope"))), 0L)
    expect_equal(nrow(dplyr::collect(entropia_llm_results(
      con,
      target_type = "item", job_type = "summary"
    ))), 1L)
  })
})

test_that("llm_results validates target_type and job_type arguments", {
  cls <- "entropia_error_invalid_argument"
  with_ai_con("full", function(con) {
    expect_error(entropia_llm_results(con, target_type = "bogus"), class = cls)
    expect_error(entropia_llm_results(con, target_type = NA_character_), class = cls)
    expect_error(entropia_llm_results(con, target_type = 42), class = cls)
    expect_error(entropia_llm_results(con, target_type = ""), class = cls)
    expect_error(entropia_llm_results(con, job_type = NA_character_), class = cls)
    expect_error(entropia_llm_results(con, job_type = 42), class = cls)
  })
})

# --- rag conversations / messages ---------------------------------------------

test_that("rag_conversations surfaces title and ms timestamps as POSIXct", {
  with_ai_con("full", function(con) {
    out <- entropia_collect(entropia_rag_conversations(con))
    expect_equal(nrow(out), 1L)
    expect_identical(out$title, "Consulta sobre la huelga")
    expect_s3_class(out$created_at, "POSIXct")
    expect_s3_class(out$updated_at, "POSIXct")
  })
})

test_that("rag_messages exposes ordered roles and parses sources JSON", {
  with_ai_con("full", function(con) {
    msgs <- entropia_rag_messages(con) |>
      dplyr::arrange(sort_index) |>
      entropia_collect()
    expect_equal(nrow(msgs), 2L)
    expect_identical(msgs$role, c("user", "assistant"))
    expect_identical(msgs$sort_index, c(0L, 1L))
    # sources is a list-column: NA for the user message, a data.frame for the
    # assistant message's citation array.
    expect_true(is.list(msgs$sources))
    expect_true(is.na(msgs$sources[[1]]))
    src <- msgs$sources[[2]]
    expect_true(is.data.frame(src))
    expect_named(src, c("chunk_id", "text", "score"))
    expect_identical(src$chunk_id, AI_CHUNK_1)
    expect_identical(src$text, "La huelga de 1920")
    expect_equal(src$score, 0.9)
    expect_s3_class(msgs$created_at, "POSIXct")
  })
})

# --- embeddings / chunks: BLOB discipline -------------------------------------

test_that("embeddings and chunks hide the embedding BLOB by default", {
  with_ai_con("full", function(con) {
    emb_vars <- as.vector(dplyr::tbl_vars(entropia_embeddings(con)))
    expect_false("embedding" %in% emb_vars)
    emb <- dplyr::collect(entropia_embeddings(con))
    expect_false("embedding" %in% names(emb))
    expect_equal(nrow(emb), 1L)

    ch_vars <- as.vector(dplyr::tbl_vars(entropia_chunks(con)))
    expect_false("embedding" %in% ch_vars)
    ch <- dplyr::collect(entropia_chunks(con))
    expect_false("embedding" %in% names(ch))
    expect_equal(nrow(ch), 1L)
  })
})

test_that("with_vector = TRUE exposes the raw f32 BLOB", {
  with_ai_con("full", function(con) {
    emb <- entropia_collect(entropia_embeddings(con, with_vector = TRUE))
    expect_true("embedding" %in% names(emb))
    expect_true(is.list(emb$embedding))
    expect_true(is.raw(emb$embedding[[1]]))
    expect_length(emb$embedding[[1]], 16L) # 4 f32 dims, little-endian

    ch <- entropia_collect(entropia_chunks(con, with_vector = TRUE))
    expect_true("embedding" %in% names(ch))
    expect_true(is.raw(ch$embedding[[1]]))
    expect_length(ch$embedding[[1]], 16L)
    # dimensions stays integer
    expect_identical(ch$dimensions, 4L)
  })
})

test_that("entropia_chunks surfaces the chunking contract values", {
  with_ai_con("full", function(con) {
    ch <- entropia_collect(entropia_chunks(con))
    expect_identical(ch$id, AI_CHUNK_1)
    expect_identical(ch$chunking_contract, "rag-chunk-800-100-char-v1")
    expect_identical(ch$embedding_model, "baai/bge-m3")
    expect_identical(ch$embedding_contract, "bge-m3-6000-char-weighted-mean-l2-v1")
    expect_identical(ch$dimensions, 4L)
    expect_identical(ch$source_kind, "extraction")
    expect_identical(ch$source_id, paste0("ext-", AI_ASSET_PDF))
    expect_identical(ch$start_char, 0L)
    expect_identical(ch$end_char, 48L)
  })
})

test_that("embeddings/chunks reject an invalid with_vector argument", {
  cls <- "entropia_error_invalid_argument"
  with_ai_con("full", function(con) {
    expect_error(entropia_embeddings(con, with_vector = NA), class = cls)
    expect_error(entropia_embeddings(con, with_vector = "yes"), class = cls)
    expect_error(entropia_embeddings(con, with_vector = c(TRUE, FALSE)), class = cls)
    expect_error(entropia_chunks(con, with_vector = NA), class = cls)
    expect_error(entropia_chunks(con, with_vector = 1), class = cls)
  })
})

# --- search_index (raw contentless FTS5) --------------------------------------

test_that("entropia_search_index is the raw contentless FTS table", {
  with_ai_con("full", function(con) {
    idx <- entropia_search_index(con)
    expect_s3_class(idx, "tbl_sql")
    expect_match(dbplyr::sql_render(idx), "fts_items")
    out <- dplyr::collect(idx)
    # One row per item; contentless FTS5 stores no column content, so every
    # declared column reads NULL without a rowid join to items.
    expect_equal(nrow(out), 3L)
    expect_named(out, c("item_id", "title", "metadata", "extracted_text"))
    expect_true(all(is.na(unlist(out))))
  })
})

# --- legacy / error paths ------------------------------------------------------

test_that("llm_results degrades without target_type on a pre-0019 schema", {
  with_ai_con("legacy-pre0019", function(con) {
    lr <- entropia_llm_results(con)
    expect_s3_class(lr, "tbl_sql")
    expect_false("target_type" %in% as.vector(dplyr::tbl_vars(lr)))
    expect_equal(nrow(dplyr::collect(lr)), 1L)
    # the absent filter errors with guidance; job_type still works
    expect_error(
      entropia_llm_results(con, target_type = "item"),
      class = "entropia_error_invalid_argument"
    )
    expect_equal(nrow(dplyr::collect(entropia_llm_results(con, job_type = "summary"))), 1L)
  })
})

test_that("embeddings reads a legacy vec_assets (contract columns tolerated)", {
  with_ai_con("legacy-pre0019", function(con) {
    emb <- entropia_embeddings(con)
    expect_s3_class(emb, "tbl_sql")
    expect_equal(nrow(dplyr::collect(emb)), 1L)
    expect_false("embedding" %in% as.vector(dplyr::tbl_vars(emb)))
    expect_true(
      "embedding" %in% as.vector(dplyr::tbl_vars(entropia_embeddings(con, with_vector = TRUE)))
    )
  })
})

test_that("AI/RAG accessors raise table_missing on schemas without them", {
  with_ai_con("mini", function(con) {
    expect_error(entropia_llm_results(con), class = "entropia_error_table_missing")
    expect_error(entropia_rag_conversations(con), class = "entropia_error_table_missing")
    expect_error(entropia_rag_messages(con), class = "entropia_error_table_missing")
    expect_error(entropia_embeddings(con), class = "entropia_error_table_missing")
    expect_error(entropia_chunks(con), class = "entropia_error_table_missing")
    expect_error(entropia_search_index(con), class = "entropia_error_table_missing")
  })
})

test_that("AI/RAG accessors reject a closed connection", {
  con <- withr::with_options(
    list(entropiaR.schema_policy = "allow"),
    entropia_connect(ent_fixture("full"))
  )
  entropia_disconnect(con)
  expect_error(entropia_llm_results(con), class = "entropia_error_invalid_connection")
  expect_error(entropia_rag_conversations(con), class = "entropia_error_invalid_connection")
  expect_error(entropia_rag_messages(con), class = "entropia_error_invalid_connection")
  expect_error(entropia_embeddings(con), class = "entropia_error_invalid_connection")
  expect_error(entropia_chunks(con), class = "entropia_error_invalid_connection")
  expect_error(entropia_search_index(con), class = "entropia_error_invalid_connection")
})
