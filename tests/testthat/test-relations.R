# Tests for Task 19 (research layer: conversations + entity/triple relations +
# llm_results reconstruction).
#
# entropia_conversation() materialises one RAG conversation with its messages
# ordered by sort_index and the sources citations parsed. entropia_entity_
# relations() lazily joins triples to item/collection context. entropia_
# reconstruct_analysis() joins llm_results back to the row they analysed
# (asset/item/collection by target_type) and parses result. All fixtures come
# from ent_fixture() (temp copies); never data-test/.

# Deterministic fixture ids (mirror data-raw/make_fixtures.R).
REL_CONV_1 <- "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1"
REL_MSG_1 <- "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2"
REL_MSG_2 <- "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb3"
REL_ITEM_1 <- "22222222-2222-4222-8222-222222222221"
REL_COLL_1 <- "11111111-1111-4111-8111-111111111111"
REL_ASSET_PDF <- "33333333-3333-4333-8333-333333333331"
REL_CHUNK_1 <- "ragchk-0000000000000000000000000000000000000000000000000000000000000001"
REL_BAD <- "dddddddd-dddd-4ddd-8ddd-dddddddddddd01"

with_rel_con <- function(name, f) {
  con <- ent_connect_fixture(name)
  on.exit(try(entropia_disconnect(con), silent = TRUE), add = TRUE)
  f(con)
}

# --- entropia_conversation -----------------------------------------------------

test_that("entropia_conversation returns the conversation and its messages", {
  with_rel_con("full", function(con) {
    out <- entropia_conversation(con, REL_CONV_1)
    expect_s3_class(out, "entropia_conversation")
    expect_named(out, c("conversation", "messages"))

    conv <- out$conversation
    expect_equal(nrow(conv), 1L)
    expect_identical(conv$id, REL_CONV_1)
    expect_identical(conv$title, "Consulta sobre la huelga")
    expect_s3_class(conv$created_at, "POSIXct")
    expect_s3_class(conv$updated_at, "POSIXct")

    msgs <- out$messages
    expect_equal(nrow(msgs), 2L)
    expect_identical(msgs$id, c(REL_MSG_1, REL_MSG_2))
    expect_identical(msgs$sort_index, c(0L, 1L))
    expect_identical(msgs$role, c("user", "assistant"))
    expect_identical(
      msgs$content,
      c("¿Que paso en la huelga?", "Hubo una huelga general en 1920.")
    )
    expect_s3_class(msgs$created_at, "POSIXct")
  })
})

test_that("conversation messages are ordered by sort_index even when inserted late", {
  path <- ent_fixture("full")
  wcon <- DBI::dbConnect(RSQLite::SQLite(), path)
  DBI::dbExecute(
    wcon,
    "INSERT INTO rag_messages (id, conversation_id, sort_index, role, content, created_at)
     VALUES (?, ?, -5, 'user', 'earlier message', 1)",
    params = list("cccccccc-cccc-4ccc-8ccc-ccccccccccc1", REL_CONV_1)
  )
  DBI::dbDisconnect(wcon)
  con <- entropia_connect(path)
  on.exit(try(entropia_disconnect(con), silent = TRUE), add = TRUE)
  out <- entropia_conversation(con, REL_CONV_1)
  expect_identical(out$messages$sort_index, c(-5L, 0L, 1L))
  expect_identical(out$messages$content[1], "earlier message")
})

test_that("conversation sources parse to a data.frame on assistant messages", {
  with_rel_con("full", function(con) {
    out <- entropia_conversation(con, REL_CONV_1)
    msgs <- out$messages
    expect_true(is.list(msgs$sources))
    expect_true(is.na(msgs$sources[[1]])) # user message has no citations
    src <- msgs$sources[[2]]
    expect_true(is.data.frame(src))
    expect_named(src, c("chunk_id", "text", "score"))
    expect_identical(src$chunk_id, REL_CHUNK_1)
    expect_identical(src$text, "La huelga de 1920")
    expect_equal(src$score, 0.9)
  })
})

test_that("conversation errors on a missing id and invalid arguments", {
  with_rel_con("full", function(con) {
    expect_error(entropia_conversation(con, REL_BAD), class = "entropia_error_not_found")
    cls <- "entropia_error_invalid_argument"
    expect_error(entropia_conversation(con, c(REL_CONV_1, REL_CONV_1)), class = cls)
    expect_error(entropia_conversation(con, NA_character_), class = cls)
    expect_error(entropia_conversation(con, ""), class = cls)
    expect_error(entropia_conversation(con, 42), class = cls)
  })
})

test_that("conversation raises table_missing on schemas without RAG tables", {
  with_rel_con("mini", function(con) {
    expect_error(entropia_conversation(con, REL_CONV_1), class = "entropia_error_table_missing")
  })
})

test_that("conversation rejects a closed connection", {
  con <- ent_connect_fixture("full")
  entropia_disconnect(con)
  expect_error(entropia_conversation(con, REL_CONV_1), class = "entropia_error_invalid_connection")
})

test_that("print method renders the title and message count", {
  with_rel_con("full", function(con) {
    out <- capture.output(print(entropia_conversation(con, REL_CONV_1)))
    expect_true(any(grepl("Consulta sobre la huelga", out, fixed = TRUE)))
    expect_true(any(grepl("2 message", out, fixed = TRUE)))
    expect_true(any(grepl("user", out, fixed = TRUE)))
    expect_true(any(grepl("assistant", out, fixed = TRUE)))
  })
})

# --- entropia_entity_relations ------------------------------------------------

test_that("entity relations is a lazy join carrying item and collection context", {
  with_rel_con("full", function(con) {
    rel <- entropia_entity_relations(con)
    expect_s3_class(rel, "tbl_sql")
    expect_false(inherits(rel, "data.frame"))
    expect_true(is.na(nrow(rel)))
    sql <- dbplyr::sql_render(rel)
    expect_match(sql, "triples")
    expect_match(sql, "LEFT JOIN")
    expect_match(sql, "items")
    expect_match(sql, "collections")
    expect_true(all(c(
      "id", "subject", "predicate", "object", "item_id", "item_title",
      "collection_id", "collection_name", "asset_id"
    ) %in% as.vector(dplyr::tbl_vars(rel))))
  })
})

test_that("entity relations resolves item and collection context on the fixture", {
  with_rel_con("full", function(con) {
    out <- dplyr::collect(entropia_entity_relations(con))
    expect_equal(nrow(out), 1L)
    expect_identical(out$id, "88888888-8888-4888-8888-888888888881")
    expect_identical(out$subject, "Juan Pérez")
    expect_identical(out$predicate, "participo_en")
    expect_identical(out$object, "la huelga")
    expect_identical(out$item_id, REL_ITEM_1)
    expect_identical(out$item_title, "Manifiesto de la huelga")
    expect_identical(out$collection_id, REL_COLL_1)
    expect_identical(out$collection_name, "Archivo de prueba")
    expect_true(is.na(out$asset_id)) # item-level triple
  })
})

test_that("entity relations rejects min_confidence (triples carry no confidence)", {
  with_rel_con("full", function(con) {
    expect_error(
      entropia_entity_relations(con, min_confidence = 0.9),
      class = "entropia_error_invalid_argument"
    )
    expect_error(
      entropia_entity_relations(con, min_confidence = 2),
      class = "entropia_error_invalid_argument"
    )
    expect_error(
      entropia_entity_relations(con, min_confidence = "high"),
      class = "entropia_error_invalid_argument"
    )
    expect_error(
      entropia_entity_relations(con, min_confidence = c(0.5, 0.9)),
      class = "entropia_error_invalid_argument"
    )
  })
})

test_that("entity relations works on legacy schemas and errors cleanly on mini", {
  with_rel_con("legacy-seconds", function(con) {
    out <- dplyr::collect(entropia_entity_relations(con))
    expect_equal(nrow(out), 1L)
    expect_identical(out$item_title, "Manifiesto de la huelga")
  })
  with_rel_con("mini", function(con) {
    expect_error(entropia_entity_relations(con), class = "entropia_error_table_missing")
  })
  con <- ent_connect_fixture("full")
  entropia_disconnect(con)
  expect_error(entropia_entity_relations(con), class = "entropia_error_invalid_connection")
})

# --- entropia_reconstruct_analysis ---------------------------------------------

test_that("reconstruct resolves an item target and parses result", {
  with_rel_con("full", function(con) {
    out <- entropia_reconstruct_analysis(con)
    expect_s3_class(out, "entropia_reconstruction")
    expect_s3_class(out, "tbl_df")
    expect_false(inherits(out, "tbl_sql"))
    expect_equal(nrow(out), 1L)
    expect_identical(out$id, paste0("llr-item-", REL_ITEM_1, "-summary"))
    expect_identical(out$target_type, "item")
    expect_identical(out$target_id, REL_ITEM_1)
    expect_identical(out$job_type, "summary")
    expect_s3_class(out$created_at, "POSIXct")
    expect_true(is.list(out$result))
    expect_identical(out$result[[1]]$summary, "Documento sobre la huelga general.")
    expect_identical(out$result[[1]]$tags, c("historia", "movimiento-obrero"))
    tgt <- out$target[[1]]
    expect_true(is.data.frame(tgt))
    expect_identical(tgt$id, REL_ITEM_1)
    expect_identical(tgt$title, "Manifiesto de la huelga")
    expect_s3_class(tgt$created_at, "POSIXct") # target row is typed too
  })
})

test_that("reconstruct resolves across asset/item/collection target types", {
  path <- ent_fixture("full")
  wcon <- DBI::dbConnect(RSQLite::SQLite(), path)
  DBI::dbExecute(
    wcon,
    "INSERT INTO llm_results (id, target_id, target_type, job_type, result, created_at)
     VALUES (?, ?, 'asset', 'summary', '{\"summary\":\"asset\"}', 1)",
    params = list("llr-asset-deadbeef-asset-summary", REL_ASSET_PDF)
  )
  DBI::dbExecute(
    wcon,
    "INSERT INTO llm_results (id, target_id, target_type, job_type, result, created_at)
     VALUES (?, ?, 'collection', 'summary', '{\"summary\":\"coll\"}', 1)",
    params = list("llr-collection-deadbeef-coll-summary", REL_COLL_1)
  )
  # an 'unknown' target_type row cannot be resolved but must not break
  DBI::dbExecute(
    wcon,
    "INSERT INTO llm_results (id, target_id, target_type, job_type, result, created_at)
     VALUES (?, ?, 'unknown', 'summary', '{}', 1)",
    params = list("llr-unknown-deadbeef-unknown-summary", REL_BAD)
  )
  DBI::dbDisconnect(wcon)
  con <- entropia_connect(path)
  on.exit(try(entropia_disconnect(con), silent = TRUE), add = TRUE)
  out <- entropia_reconstruct_analysis(con)
  expect_equal(nrow(out), 4L)
  by_type <- split(out, out$target_type)
  expect_identical(by_type$asset$target[[1]]$id, REL_ASSET_PDF)
  expect_identical(by_type$collection$target[[1]]$name, "Archivo de prueba")
  expect_identical(by_type$item$target[[1]]$id, REL_ITEM_1)
  expect_true(is.null(by_type$unknown$target[[1]])) # unknown type stays unresolved
})

test_that("reconstruct filters by target and job_type", {
  with_rel_con("full", function(con) {
    out <- entropia_reconstruct_analysis(con, target = REL_ITEM_1)
    expect_equal(nrow(out), 1L)
    expect_identical(out$target_id, REL_ITEM_1)
    expect_false(is.null(out$target[[1]]))

    empty <- entropia_reconstruct_analysis(con, target = REL_BAD)
    expect_equal(nrow(empty), 0L)
    expect_s3_class(empty, "entropia_reconstruction")

    jt <- entropia_reconstruct_analysis(con, job_type = "summary")
    expect_equal(nrow(jt), 1L)
    jt2 <- entropia_reconstruct_analysis(con, job_type = "nope")
    expect_equal(nrow(jt2), 0L)
  })
})

test_that("reconstruct validates target and job_type arguments", {
  cls <- "entropia_error_invalid_argument"
  with_rel_con("full", function(con) {
    expect_error(entropia_reconstruct_analysis(con, target = c("a", "b")), class = cls)
    expect_error(entropia_reconstruct_analysis(con, target = NA_character_), class = cls)
    expect_error(entropia_reconstruct_analysis(con, target = 42), class = cls)
    expect_error(entropia_reconstruct_analysis(con, target = ""), class = cls)
    expect_error(entropia_reconstruct_analysis(con, job_type = NA_character_), class = cls)
    expect_error(entropia_reconstruct_analysis(con, job_type = 42), class = cls)
  })
})

test_that("reconstruct degrades on legacy-pre0019 (no target_type column)", {
  with_rel_con("legacy-pre0019", function(con) {
    out <- entropia_reconstruct_analysis(con)
    expect_s3_class(out, "entropia_reconstruction")
    expect_equal(nrow(out), 1L)
    expect_true(all(is.na(out$target_type)))
    expect_true(is.null(out$target[[1]])) # cannot resolve without a type
    expect_identical(out$result[[1]]$summary, "Documento sobre la huelga general.")
    expect_s3_class(out$created_at, "POSIXct")
  })
})

test_that("reconstruct raises table_missing on mini and rejects a closed connection", {
  with_rel_con("mini", function(con) {
    expect_error(entropia_reconstruct_analysis(con), class = "entropia_error_table_missing")
  })
  con <- ent_connect_fixture("full")
  entropia_disconnect(con)
  expect_error(entropia_reconstruct_analysis(con), class = "entropia_error_invalid_connection")
})

test_that("print method summarizes by target type and handles the empty case", {
  with_rel_con("full", function(con) {
    out <- capture.output(print(entropia_reconstruct_analysis(con)))
    expect_true(any(grepl("Reconstructed LLM analyses: 1 row", out, fixed = TRUE)))
    expect_true(any(grepl("item", out, fixed = TRUE)))
  })
  with_rel_con("full", function(con) {
    empty <- entropia_reconstruct_analysis(con, target = REL_BAD)
    out <- capture.output(print(empty))
    expect_true(any(grepl("0 row", out, fixed = TRUE)))
  })
})
