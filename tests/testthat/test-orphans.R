# Tests for Task 18 (entropia_orphans, relationship integrity).
#
# entropia_orphans() scans the schema's conceptual foreign keys and reports one
# row per broken reference (kind/table/id/column/ref_table/message). The full
# fixture is internally consistent, so a clean run yields zero findings. Each
# relationship kind is exercised by inserting a synthetic broken row into a
# throw-away fixture copy (never the source artifact, never data-test/), mirror
# the test-quality.R pattern.

ORPH_COLL_1 <- "11111111-1111-4111-8111-111111111111"
ORPH_ITEM_1 <- "22222222-2222-4222-8222-222222222221"
ORPH_ITEM_2 <- "22222222-2222-4222-8222-222222222222"
ORPH_ITEM_3 <- "22222222-2222-4222-8222-222222222223"
ORPH_ASSET_PDF <- "33333333-3333-4333-8333-333333333331"
ORPH_ASSET_PAGE1 <- "33333333-3333-4333-8333-333333333332"
ORPH_TOPIC_1 <- "99999999-9999-4999-8999-999999999991"

# Synthetic ids that exist nowhere; each is a distinct, obviously-dangling UUID.
ORPH_BAD <- sprintf("dddddddd-dddd-4ddd-8ddd-dddddddddd%02x", seq_len(24))

with_orphans_con <- function(name, f) {
  con <- ent_connect_fixture(name)
  on.exit(try(entropia_disconnect(con), silent = TRUE), add = TRUE)
  f(con)
}

# Insert synthetic broken rows into a throw-away copy of the full fixture:
# run `fill(wcon)` against a writable DBI connection, close it, then return a
# fresh read-only entropia_connect on the same copy. Mirrors test-quality.R.
with_broken <- function(fill, f) {
  path <- ent_fixture("full")
  wcon <- DBI::dbConnect(RSQLite::SQLite(), path)
  fill(wcon)
  DBI::dbDisconnect(wcon)
  con <- entropia_connect(path)
  on.exit(try(entropia_disconnect(con), silent = TRUE), add = TRUE)
  f(con)
}

# --- clean fixtures ----------------------------------------------------------

test_that("clean fixtures report zero orphaned rows", {
  with_orphans_con("full", function(con) {
    res <- entropia_orphans(con)
    expect_s3_class(res, "entropia_orphans")
    expect_s3_class(res, "tbl_df")
    expect_false(inherits(res, "tbl_sql"))
    expect_identical(
      names(res),
      c("kind", "table", "id", "column", "ref_table", "message")
    )
    expect_equal(nrow(res), 0L)
  })
  with_orphans_con("mini", function(con) {
    expect_equal(nrow(entropia_orphans(con)), 0L)
  })
  with_orphans_con("legacy-pre0019", function(con) {
    expect_equal(nrow(entropia_orphans(con)), 0L)
  })
  with_orphans_con("legacy-seconds", function(con) {
    expect_equal(nrow(entropia_orphans(con)), 0L)
  })
  with_orphans_con("unknown-version", function(con) {
    expect_equal(nrow(entropia_orphans(con)), 0L)
  })
})

# --- items -> collections, assets -> items, assets -> parent ------------------

test_that("dangling item collection and asset item references are reported", {
  with_broken(function(w) {
    DBI::dbExecute(
      w,
      "INSERT INTO items (id, title, collection_id, created_at, updated_at)
       VALUES (?, 'orphan item', ?, 1, 1)",
      params = list(ORPH_BAD[1], ORPH_BAD[2])
    )
    DBI::dbExecute(
      w,
      "INSERT INTO assets (id, item_id, path, type, created_at)
       VALUES (?, ?, 'orphan.jpg', 'image', 1)",
      params = list(ORPH_BAD[3], ORPH_BAD[4])
    )
  }, function(con) {
    res <- entropia_orphans(con)

    item_orph <- res[res$kind == "item_collection", ]
    expect_equal(nrow(item_orph), 1L)
    expect_identical(item_orph$table, "items")
    expect_identical(item_orph$id, ORPH_BAD[1])
    expect_identical(item_orph$column, "collection_id")
    expect_identical(item_orph$ref_table, "collections")
    expect_match(item_orph$message, "items", fixed = TRUE)

    asset_orph <- res[res$kind == "asset_item", ]
    expect_equal(nrow(asset_orph), 1L)
    expect_identical(asset_orph$table, "assets")
    expect_identical(asset_orph$id, ORPH_BAD[3])
    expect_identical(asset_orph$column, "item_id")
    expect_identical(asset_orph$ref_table, "items")
  })
})

test_that("a dangling asset parent and a resolved one are handled", {
  with_broken(function(w) {
    # broken page: valid item, dangling parent
    DBI::dbExecute(
      w,
      "INSERT INTO assets (id, item_id, path, type, created_at, parent_asset_id)
       VALUES (?, ?, 'p1.pdf', 'pdf', 1, ?)",
      params = list(ORPH_BAD[5], ORPH_ITEM_1, ORPH_BAD[6])
    )
    # healthy page: valid item, existing parent (ASSET_PDF) -> not an orphan
    DBI::dbExecute(
      w,
      "INSERT INTO assets (id, item_id, path, type, created_at, parent_asset_id, page_number)
       VALUES (?, ?, 'p2.pdf', 'pdf', 1, ?, 3)",
      params = list(ORPH_BAD[7], ORPH_ITEM_1, ORPH_ASSET_PDF)
    )
  }, function(con) {
    res <- entropia_orphans(con)
    parent_orph <- res[res$kind == "asset_parent", ]
    expect_equal(nrow(parent_orph), 1L)
    expect_identical(parent_orph$id, ORPH_BAD[5])
    expect_identical(parent_orph$ref_table, "assets")
    # the healthy page is not flagged by any kind
    expect_false(ORPH_BAD[7] %in% res$id)
  })
})

# --- text layers -> assets ----------------------------------------------------

test_that("extraction/transcription/layout orphans are reported by asset_id", {
  with_broken(function(w) {
    DBI::dbExecute(
      w,
      "INSERT INTO extractions (id, asset_id, text_content, method, created_at)
       VALUES (?, ?, 'x', 'ocr', 1)",
      params = list(paste0("ext-", ORPH_BAD[8]), ORPH_BAD[8])
    )
    DBI::dbExecute(
      w,
      "INSERT INTO transcriptions (id, asset_id, text_content, model, created_at)
       VALUES (?, ?, 'x', 'm', 1)",
      params = list(paste0("trx-", ORPH_BAD[9]), ORPH_BAD[9])
    )
    DBI::dbExecute(
      w,
      paste0(
        "INSERT INTO layouts (id, asset_id, regions, blocks, model, ",
        "image_width, image_height, created_at) VALUES ",
        "(?, ?, '[]', '[]', 'm', 100, 200, 1)"
      ),
      params = list(paste0("lay-", ORPH_BAD[10]), ORPH_BAD[10])
    )
  }, function(con) {
    res <- entropia_orphans(con)
    expect_identical(res$kind[res$kind == "extraction_asset"], "extraction_asset")
    expect_identical(
      res$id[res$kind == "extraction_asset"],
      paste0("ext-", ORPH_BAD[8])
    )
    expect_identical(
      res$id[res$kind == "transcription_asset"],
      paste0("trx-", ORPH_BAD[9])
    )
    expect_identical(
      res$id[res$kind == "layout_asset"],
      paste0("lay-", ORPH_BAD[10])
    )
    expect_identical(res$column[res$kind == "extraction_asset"], "asset_id")
    expect_identical(res$ref_table[res$kind == "extraction_asset"], "assets")
  })
})

# --- entities / triples -> items & assets -------------------------------------

test_that("entity and triple item/asset orphans are reported", {
  with_broken(function(w) {
    # one entity whose item_id AND asset_id are both dangling -> two findings
    DBI::dbExecute(
      w,
      "INSERT INTO entities (id, item_id, entity_type, value, asset_id)
       VALUES (?, ?, 'person', 'x', ?)",
      params = list(ORPH_BAD[11], ORPH_BAD[12], ORPH_BAD[13])
    )
    DBI::dbExecute(
      w,
      "INSERT INTO triples (id, item_id, subject, predicate, object, asset_id)
       VALUES (?, ?, 's', 'p', 'o', ?)",
      params = list(ORPH_BAD[14], ORPH_BAD[15], ORPH_BAD[16])
    )
  }, function(con) {
    res <- entropia_orphans(con)
    expect_identical(res$id[res$kind == "entity_item"], ORPH_BAD[11])
    expect_identical(res$ref_table[res$kind == "entity_item"], "items")
    expect_identical(res$id[res$kind == "entity_asset"], ORPH_BAD[11])
    expect_identical(res$ref_table[res$kind == "entity_asset"], "assets")
    expect_identical(res$id[res$kind == "triple_item"], ORPH_BAD[14])
    expect_identical(res$ref_table[res$kind == "triple_item"], "items")
    expect_identical(res$id[res$kind == "triple_asset"], ORPH_BAD[14])
    expect_identical(res$ref_table[res$kind == "triple_asset"], "assets")
  })
})

# --- notes / annotations ------------------------------------------------------

test_that("note and annotation asset orphans are reported; NULL asset_id is not", {
  with_broken(function(w) {
    # broken note: dangling item AND dangling asset
    DBI::dbExecute(
      w,
      "INSERT INTO notes (id, item_id, content, created_at, updated_at, asset_id)
       VALUES (?, ?, 'x', 1, 1, ?)",
      params = list(ORPH_BAD[17], ORPH_BAD[18], ORPH_BAD[19])
    )
    # item-level note: NULL asset_id (valid) with a valid item -> no findings
    DBI::dbExecute(
      w,
      "INSERT INTO notes (id, item_id, content, created_at, updated_at, asset_id)
       VALUES (?, ?, 'item-level', 1, 1, NULL)",
      params = list(ORPH_BAD[20], ORPH_ITEM_1)
    )
    DBI::dbExecute(
      w,
      paste0(
        "INSERT INTO annotations ",
        "(id, asset_id, kind, color, x, y, width, height, created_at, updated_at) ",
        "VALUES (?, ?, 'rectangle', '#000', 0, 0, 1, 1, 1, 1)"
      ),
      params = list(ORPH_BAD[21], ORPH_BAD[22])
    )
  }, function(con) {
    res <- entropia_orphans(con)
    expect_identical(res$id[res$kind == "note_item"], ORPH_BAD[17])
    expect_identical(res$id[res$kind == "note_asset"], ORPH_BAD[17])
    expect_identical(res$id[res$kind == "annotation_asset"], ORPH_BAD[21])
    # the item-level note (NULL asset_id, valid item) is never flagged
    expect_false(ORPH_BAD[20] %in% res$id)
    # the fixture's own notes already carry NULL asset_id on a clean run
    expect_false(any(res$kind == "note_asset" & res$id == "55555555-5555-4555-8555-555555555551"))
  })
})

# --- llm_results -> target ----------------------------------------------------

test_that("llm_results targets resolve by target_type; unknown is not checkable", {
  with_broken(function(w) {
    # dangling asset target -> llm_target against assets
    DBI::dbExecute(
      w,
      "INSERT INTO llm_results (id, target_id, target_type, job_type, result, created_at)
       VALUES (?, ?, 'asset', 'summary', '{}', 1)",
      params = list(ORPH_BAD[23], ORPH_BAD[24])
    )
    # dangling collection target -> llm_target against collections
    DBI::dbExecute(
      w,
      "INSERT INTO llm_results (id, target_id, target_type, job_type, result, created_at)
       VALUES (?, ?, 'collection', 'summary', '{}', 1)",
      params = list(ORPH_BAD[1], ORPH_BAD[2])
    )
    # 'unknown' target_type with a dangling id: not checkable -> not reported
    DBI::dbExecute(
      w,
      "INSERT INTO llm_results (id, target_id, target_type, job_type, result, created_at)
       VALUES (?, ?, 'unknown', 'summary', '{}', 1)",
      params = list(ORPH_BAD[3], ORPH_BAD[4])
    )
  }, function(con) {
    res <- entropia_orphans(con)
    llm <- res[res$kind == "llm_target", ]
    expect_equal(nrow(llm), 2L)
    expect_true(all(c("assets", "collections") %in% llm$ref_table))
    expect_identical(llm$ref_table[llm$id == ORPH_BAD[23]], "assets")
    expect_identical(llm$ref_table[llm$id == ORPH_BAD[1]], "collections")
    # the 'unknown' row is not among the findings
    expect_false(ORPH_BAD[3] %in% res$id)
  })
})

# --- rag_messages / rag_chunks / item_topics ----------------------------------

test_that("message, chunk and item_topic orphans are reported", {
  with_broken(function(w) {
    DBI::dbExecute(
      w,
      "INSERT INTO rag_messages (id, conversation_id, sort_index, role, content, created_at)
       VALUES (?, ?, 0, 'user', 'orphan msg', 1)",
      params = list(ORPH_BAD[5], ORPH_BAD[6])
    )
    DBI::dbExecute(
      w,
      "INSERT INTO rag_chunks
         (id, asset_id, item_id, source_kind, source_id, chunk_ordinal,
          text_content, start_char, end_char, source_text_hash, chunking_contract,
          embedding, embedding_model, embedding_contract, dimensions)
       VALUES (?, ?, ?, 'extraction', ?, 0, 'orphan chunk', 0, 8, 'orphan-hash',
               'rag-chunk-800-100-char-v1', x'0000803f', 'test-model', 'test-contract', 4)",
      params = list(ORPH_BAD[7], ORPH_BAD[8], ORPH_BAD[9], ORPH_BAD[10])
    )
    DBI::dbExecute(
      w,
      "INSERT INTO item_topics (id, item_id, topic_id, created_at)
       VALUES (?, ?, ?, 1)",
      params = list(ORPH_BAD[11], ORPH_BAD[12], ORPH_BAD[13])
    )
  }, function(con) {
    res <- entropia_orphans(con)
    expect_identical(res$id[res$kind == "message_conversation"], ORPH_BAD[5])
    expect_identical(res$ref_table[res$kind == "message_conversation"], "rag_conversations")
    expect_identical(res$id[res$kind == "chunk_item"], ORPH_BAD[7])
    expect_identical(res$id[res$kind == "chunk_asset"], ORPH_BAD[7])
    expect_identical(res$id[res$kind == "item_topic_item"], ORPH_BAD[11])
    expect_identical(res$id[res$kind == "item_topic_topic"], ORPH_BAD[11])
    expect_identical(res$ref_table[res$kind == "item_topic_topic"], "topics")
  })
})

# --- ordering and structure ---------------------------------------------------

test_that("findings are ordered deterministically by kind, table, id", {
  with_broken(function(w) {
    DBI::dbExecute(
      w,
      "INSERT INTO items (id, title, collection_id, created_at, updated_at)
       VALUES (?, 'b', ?, 1, 1), (?, 'a', ?, 1, 1)",
      params = list(ORPH_BAD[1], ORPH_BAD[2], ORPH_BAD[3], ORPH_BAD[4])
    )
  }, function(con) {
    res <- entropia_orphans(con)
    kind_orph <- res[res$kind == "item_collection", ]
    expect_identical(kind_orph$id, sort(kind_orph$id))
    # the whole table is sorted by kind, then table, then id
    expect_true(all(res$kind == sort(res$kind)))
  })
})

# --- schema degradation -------------------------------------------------------

test_that("mini schema skips absent tables without error", {
  with_orphans_con("mini", function(con) {
    res <- entropia_orphans(con)
    expect_s3_class(res, "entropia_orphans")
    expect_equal(nrow(res), 0L)
  })
})

test_that("legacy-pre0019 skips the llm target check without error", {
  with_orphans_con("legacy-pre0019", function(con) {
    res <- entropia_orphans(con)
    expect_equal(nrow(res), 0L)
    expect_false("llm_target" %in% res$kind)
  })
})

# --- error paths and print ----------------------------------------------------

test_that("orphans rejects a closed connection", {
  con <- ent_connect_fixture("full")
  entropia_disconnect(con)
  expect_error(entropia_orphans(con), class = "entropia_error_invalid_connection")
})

test_that("print method summarizes findings and handles the empty case", {
  with_broken(function(w) {
    DBI::dbExecute(
      w,
      "INSERT INTO items (id, title, collection_id, created_at, updated_at)
       VALUES (?, 'orphan item', ?, 1, 1)",
      params = list(ORPH_BAD[1], ORPH_BAD[2])
    )
  }, function(con) {
    out <- capture.output(print(entropia_orphans(con)))
    expect_true(any(grepl("Found 1 orphaned row", out)))
    expect_true(any(grepl("item_collection", out)))
  })
  with_orphans_con("full", function(con) {
    expect_message(
      print(entropia_orphans(con)),
      "No orphaned rows detected"
    )
  })
})
