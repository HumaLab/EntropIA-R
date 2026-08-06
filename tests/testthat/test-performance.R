# Performance smoke tests (Task 30).
#
# EXPLAIN QUERY PLAN on the hot paths -- corpus join, FTS search, and the
# entity-relations join -- asserting the invariant that every *lookup* table in
# a join resolves through an index, never a full scan. Only the driving base
# table of a query may be SCANned (reading it is unavoidable); every other table
# must be reached via `SEARCH ... USING INDEX` (or an INTEGER PRIMARY KEY /
# sqlite_autoindex lookup).
#
# The fixture tables are tiny (3-5 rows), but SQLite's planner assumes
# ~1,000,000 rows per table when no ANALYZE statistics exist, so the plan is
# stable: with the right index present it always prefers the index. The
# assertions below therefore pin the *plan shape* (no SCAN of a joined table)
# rather than exact join order or index names, keeping them robust across
# RSQLite-bundled SQLite versions on all CI platforms.

# Render EXPLAIN QUERY PLAN for a lazy tbl_sql on a connection.
ent_explain_plan <- function(con, tbl) {
  DBI::dbGetQuery(
    con,
    paste0("EXPLAIN QUERY PLAN ", as.character(dbplyr::sql_render(tbl)))
  )
}

# The table names that appear on the left of a `SCAN` row in a query plan.
ent_scanned_tables <- function(plan) {
  scans <- plan$detail[grepl("^SCAN ", plan$detail)]
  if (length(scans) == 0L) {
    return(character(0))
  }
  vapply(
    strsplit(sub("^SCAN ", "", scans), "\\s+"),
    function(x) x[[1L]],
    character(1)
  )
}

with_perf_con <- function(name, f) {
  con <- ent_connect_fixture(name)
  on.exit(try(entropia_disconnect(con), silent = TRUE), add = TRUE)
  f(con)
}

# --- corpus join --------------------------------------------------------------

test_that("corpus join resolves every lookup table through an index", {
  with_perf_con("full", function(con) {
    plan <- ent_explain_plan(con, entropia_corpus(con))
    detail <- plan$detail
    scanned <- ent_scanned_tables(plan)

    # The four joined lookup tables must never be fully scanned: collections,
    # assets, and the two 1:1 text tables all resolve via SEARCH ... USING.
    joined <- c("collections", "assets", "extractions", "transcriptions")
    expect_false(any(joined %in% scanned))

    # And each of them contributes an index-based SEARCH row.
    searches <- detail[grepl("^SEARCH ", detail)]
    expect_gte(length(searches), length(joined))
    expect_true(all(grepl("USING INDEX|USING COVERING INDEX", searches)))
  })
})

test_that("filtered corpus join drives into items by collection index", {
  with_perf_con("full", function(con) {
    plan <- ent_explain_plan(
      con,
      entropia_corpus(con, collections = "Collection One")
    )
    detail <- plan$detail

    # The collection-name filter makes SQLite scan collections (the driving
    # table) and reach items through idx_items_collection; the asset/text
    # lookups stay index-based.
    expect_true(any(grepl("SEARCH items USING INDEX idx_items_collection", detail)))
    joined <- c("assets", "extractions", "transcriptions")
    expect_false(any(joined %in% ent_scanned_tables(plan)))
  })
})

# --- FTS search ---------------------------------------------------------------

test_that("items search uses the FTS virtual-table index and a rowid PK join", {
  with_perf_con("full", function(con) {
    plan <- ent_explain_plan(con, entropia_search(con, "huelga"))
    detail <- plan$detail
    expect_true(any(grepl("SCAN fts_items VIRTUAL TABLE INDEX", detail)))
    expect_true(any(grepl("SEARCH i USING INTEGER PRIMARY KEY", detail)))
    # The `items` lookup is a point search per matched rowid -- never a scan.
    expect_false("items" %in% ent_scanned_tables(plan))
  })
})

test_that("chunks search uses the FTS virtual-table index and a chunk_id PK join", {
  with_perf_con("full", function(con) {
    plan <- ent_explain_plan(con, entropia_search(con, "huelga", index = "chunks"))
    detail <- plan$detail
    expect_true(any(grepl("SCAN rag_chunks_fts VIRTUAL TABLE INDEX", detail)))
    expect_true(any(grepl("SEARCH c USING INDEX", detail)))
  })
})

# --- entity relations ---------------------------------------------------------

test_that("entity-relations join resolves items and collections by primary key", {
  with_perf_con("full", function(con) {
    plan <- ent_explain_plan(con, entropia_entity_relations(con))
    detail <- plan$detail
    # triples is the driving scan; items and collections are PK lookups.
    expect_true(any(grepl("SEARCH items USING INDEX sqlite_autoindex_items_1", detail)))
    expect_true(any(grepl("SEARCH collections USING INDEX sqlite_autoindex_collections_1", detail)))
    expect_false(any(c("items", "collections") %in% ent_scanned_tables(plan)))
  })
})
