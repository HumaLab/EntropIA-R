suppressMessages(devtools::load_all("G:/EntropIA-Stack/EntropIA-R", quiet = TRUE))
con <- entropiaR::entropia_connect("G:/EntropIA-Stack/EntropIA-R/tests/testthat/fixtures/full.sqlite", validate = FALSE)

build_sql <- function(query, index = "items", limit = NULL) {
  q <- DBI::dbQuoteString(con, query)
  if (index == "items") {
    sql <- paste0("SELECT i.*, bm25(fts_items) AS rank FROM fts_items JOIN items i ON i.rowid = fts_items.rowid WHERE fts_items MATCH ", q)
  } else {
    sql <- paste0("SELECT c.*, bm25(rag_chunks_fts) AS rank FROM rag_chunks_fts JOIN rag_chunks c ON c.id = rag_chunks_fts.chunk_id WHERE rag_chunks_fts MATCH ", q)
  }
  if (!is.null(limit)) sql <- paste0(sql, "\nLIMIT ", as.integer(limit))
  dbplyr::sql(sql)
}

t <- dplyr::tbl(con, build_sql("huelga"))
cat("render:\n"); print(dbplyr::sql_render(t))
cat("\ncollect (typed conn):\n"); print(dplyr::collect(t))

t2 <- dplyr::tbl(con, build_sql("huelga", "chunks"))
t2 <- dplyr::select(t2, -dplyr::any_of("embedding"))
cat("\nchunks render (no embedding):\n"); print(dbplyr::sql_render(t2))
cat("\nchunks vars:", paste(dplyr::tbl_vars(t2), collapse=", "), "\n")
print(dplyr::collect(t2))

# mini fixture: table missing behavior
conm <- entropiaR::entropia_connect("G:/EntropIA-Stack/EntropIA-R/tests/testthat/fixtures/mini.sqlite", validate = FALSE)
res <- tryCatch(dplyr::tbl(conm, build_sql("x")), error = function(e) paste("ERR:", conditionMessage(e)))
cat("\nmini tbl:", if (is.character(res)) substr(res, 1, 80) else "OK", "\n")
entropiaR::entropia_disconnect(conm)
entropiaR::entropia_disconnect(con)
