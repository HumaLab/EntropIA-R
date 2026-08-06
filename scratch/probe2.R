suppressMessages(devtools::load_all("G:/EntropIA-Stack/EntropIA-R", quiet = TRUE))
fixture <- "G:/EntropIA-Stack/EntropIA-R/tests/testthat/fixtures/full.sqlite"
con <- DBI::dbConnect(RSQLite::SQLite(), fixture)

try_q <- function(query, label) {
  q <- DBI::dbQuoteString(con, query)
  sql <- paste0("SELECT count(*) AS n FROM fts_items WHERE fts_items MATCH ", q)
  res <- tryCatch(DBI::dbGetQuery(con, sql)$n, error = function(e) paste("ERR:", conditionMessage(e)))
  cat(sprintf("%-28s -> %s\n", label, paste(res, collapse=",")))
}
try_q("huelga", "huelga")
try_q("huelga sindicato", "multi-word (implicit AND)")
try_q("' ; DROP TABLE --", "injection-ish")
try_q("''; DROP TABLE fts_items; --", "injection 2")
try_q("La huelga general", "phrase tokens")
try_q("huelga OR marcha", "OR operator")
try_q('"(huelga"', "open paren")
try_q('"', "bare quote")
try_q("huelga*", "prefix")

# chunk index
q <- DBI::dbQuoteString(con, "huelga")
sql <- paste0("SELECT c.*, bm25(rag_chunks_fts) AS rank FROM rag_chunks_fts JOIN rag_chunks c ON c.id = rag_chunks_fts.chunk_id WHERE rag_chunks_fts MATCH ", q)
res <- tryCatch(DBI::dbGetQuery(con, sql), error = function(e) paste("ERR:", conditionMessage(e)))
cat("\nchunks huelga:\n"); print(res)

# does table survive?
tabs <- DBI::dbListTables(con)
cat("\nfts_items still exists:", "fts_items" %in% tabs, " items:", "items" %in% tabs, "\n")
DBI::dbDisconnect(con)
