# Tests for Task 14 (entropia_search).
#
# Parameter-safe FTS5 search: the user query is dbQuoteString-escaped into a
# SQL string literal before splicing into MATCH (injection-safe); the `items`
# index joins fts_items.rowid -> items.rowid (contentless contract); the
# `chunks` index joins rag_chunks_fts.chunk_id -> rag_chunks.id; results are a
# lazy tbl_sql ordered by BM25 rank. All fixtures come from ent_fixture() (temp
# copies); never data-test/.

SEARCH_ITEM_1 <- "22222222-2222-4222-8222-222222222221"
SEARCH_CHUNK_1 <- "ragchk-0000000000000000000000000000000000000000000000000000000000000001"

with_search_con <- function(name, f) {
  con <- ent_connect_fixture(name)
  on.exit(try(entropia_disconnect(con), silent = TRUE), add = TRUE)
  f(con)
}

# --- laziness and shape ------------------------------------------------------

test_that("entropia_search returns a lazy tbl_sql", {
  with_search_con("full", function(con) {
    res <- entropia_search(con, "huelga")
    expect_s3_class(res, "tbl_sql")
    expect_false(inherits(res, "data.frame"))
    expect_true(is.na(nrow(res)))
    # rank-eligible ordering pushed down to SQLite
    sql <- dbplyr::sql_render(res)
    expect_match(sql, "MATCH")
    expect_match(sql, "JOIN items")
    expect_match(sql, "bm25")
    expect_match(sql, "ORDER BY")
    expect_match(sql, "rank")
  })
})

test_that("entropia_search chunks index renders a chunk_id join and no BLOB", {
  with_search_con("full", function(con) {
    res <- entropia_search(con, "huelga", index = "chunks")
    expect_s3_class(res, "tbl_sql")
    sql <- dbplyr::sql_render(res)
    expect_match(sql, "rag_chunks_fts")
    expect_match(sql, "JOIN rag_chunks")
    expect_false("embedding" %in% as.vector(dplyr::tbl_vars(res)))
  })
})

# --- known-term results on the full fixture -----------------------------------

test_that("items search returns the items whose text or title matches", {
  with_search_con("full", function(con) {
    res <- entropia_collect(entropia_search(con, "huelga"))
    # "huelga" appears in item 1's title + extraction and item 2's transcription.
    expect_equal(nrow(res), 2L)
    expect_setequal(res$title, c("Manifiesto de la huelga", "Carta al sindicato"))
    expect_true(all(res$id %in% c(SEARCH_ITEM_1, "22222222-2222-4222-8222-222222222222")))
    expect_true(is.numeric(res$rank))
  })
})

test_that("chunks search returns matching rag_chunks without the embedding BLOB", {
  with_search_con("full", function(con) {
    res <- entropia_collect(entropia_search(con, "huelga", index = "chunks"))
    expect_equal(nrow(res), 1L)
    expect_identical(res$id, SEARCH_CHUNK_1)
    expect_identical(res$text_content, "La huelga general de 1920 movilizo a los obreros.")
    expect_identical(res$source_kind, "extraction")
    expect_false("embedding" %in% names(res))
  })
})

test_that("multi-word queries combine terms (implicit AND)", {
  with_search_con("full", function(con) {
    res <- entropia_collect(entropia_search(con, "huelga sindicato"))
    # only "Carta al sindicato" carries both terms (sindicato in title,
    # huelga in its transcription); item 1 has no sindicato.
    expect_equal(nrow(res), 1L)
    expect_identical(res$title, "Carta al sindicato")
  })
})

test_that("limit truncates and validates", {
  with_search_con("full", function(con) {
    res <- entropia_collect(entropia_search(con, "huelga", limit = 1))
    expect_equal(nrow(res), 1L)
    expect_identical(res$title, "Manifiesto de la huelga") # best BM25 rank first
    cls <- "entropia_error_invalid_argument"
    expect_error(entropia_search(con, "huelga", limit = 0), class = cls)
    expect_error(entropia_search(con, "huelga", limit = -1), class = cls)
    expect_error(entropia_search(con, "huelga", limit = 1.5), class = cls)
    expect_error(entropia_search(con, "huelga", limit = Inf), class = cls)
    expect_error(entropia_search(con, "huelga", limit = "3"), class = cls)
    expect_error(entropia_search(con, "huelga", limit = c(1, 2)), class = cls)
  })
})

# --- argument validation ------------------------------------------------------

test_that("empty or malformed queries error", {
  cls <- "entropia_error_invalid_argument"
  with_search_con("full", function(con) {
    expect_error(entropia_search(con, ""), class = cls)
    expect_error(entropia_search(con, "   "), class = cls)
    expect_error(entropia_search(con, NA_character_), class = cls)
    expect_error(entropia_search(con, character(0)), class = cls)
    expect_error(entropia_search(con, c("a", "b")), class = cls)
    expect_error(entropia_search(con, 42), class = cls)
  })
})

test_that("entropia_search validates the index argument", {
  cls <- "entropia_error_invalid_argument"
  with_search_con("full", function(con) {
    expect_error(entropia_search(con, "huelga", index = "bogus"), class = cls)
    expect_error(entropia_search(con, "huelga", index = NA_character_), class = cls)
    expect_error(entropia_search(con, "huelga", index = 42), class = cls)
    # the explicit full default resolves like match.arg(): to the first choice
    expect_s3_class(entropia_search(con, "huelga", index = c("items", "chunks")), "tbl_sql")
  })
})

# --- injection safety ----------------------------------------------------------

test_that("an SQL injection attempt is inert", {
  with_search_con("full", function(con) {
    res <- entropia_search(con, "'; DROP TABLE --")
    expect_s3_class(res, "tbl_sql")
    # The quoted literal is inert: collecting either raises an FTS5 syntax error
    # (the injected statement is never executed) or returns no rows.
    out <- tryCatch(suppressWarnings(dplyr::collect(res)), error = function(e) NULL)
    # The tables survived and their contents are intact.
    expect_true(DBI::dbExistsTable(con, "items"))
    expect_true(DBI::dbExistsTable(con, "fts_items"))
    expect_equal(nrow(dplyr::collect(entropia_items(con))), 3L)
    expect_equal(nrow(dplyr::collect(entropia_search_index(con))), 3L)
  })
})

test_that("a quoted injection attempt is inert on the chunks index too", {
  with_search_con("full", function(con) {
    res <- entropia_search(con, "\"; DROP TABLE rag_chunks; --", index = "chunks")
    out <- tryCatch(suppressWarnings(dplyr::collect(res)), error = function(e) NULL)
    expect_true(DBI::dbExistsTable(con, "rag_chunks"))
    expect_true(DBI::dbExistsTable(con, "rag_chunks_fts"))
    expect_equal(nrow(dplyr::collect(entropia_chunks(con))), 1L)
  })
})

# --- contentless join correctness ----------------------------------------------

test_that("contentless items search returns real item rows (non-NULL text)", {
  with_search_con("full", function(con) {
    # fts_items alone reads NULL in every column (test-ai.R); the search join
    # must return the joined items row with real content instead.
    res <- entropia_collect(entropia_search(con, "huelga"))
    expect_true(nrow(res) >= 1L)
    expect_false(anyNA(res$id))
    expect_false(anyNA(res$title))
    expect_false(anyNA(res$created_at))
    item_ids <- dplyr::collect(entropia_items(con))$id
    expect_true(all(res$id %in% item_ids))
  })
})

# --- legacy / error paths ------------------------------------------------------

test_that("entropia_search raises table_missing on schemas without FTS", {
  with_search_con("mini", function(con) {
    expect_error(entropia_search(con, "huelga"), class = "entropia_error_table_missing")
    expect_error(
      entropia_search(con, "huelga", index = "chunks"),
      class = "entropia_error_table_missing"
    )
  })
})

test_that("entropia_search works on the legacy-pre0019 schema and rejects a closed connection", {
  with_search_con("legacy-pre0019", function(con) {
    expect_equal(nrow(dplyr::collect(entropia_search(con, "huelga"))), 2L)
    expect_equal(nrow(dplyr::collect(entropia_search(con, "huelga", index = "chunks"))), 1L)
  })
  con <- withr::with_options(
    list(entropiaR.schema_policy = "allow"),
    entropia_connect(ent_fixture("full"))
  )
  entropia_disconnect(con)
  expect_error(entropia_search(con, "huelga"), class = "entropia_error_invalid_connection")
})
