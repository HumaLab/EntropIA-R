suppressMessages(devtools::load_all("G:/EntropIA-Stack/EntropIA-R", quiet = TRUE))
fixture <- "G:/EntropIA-Stack/EntropIA-R/tests/testthat/fixtures/full.sqlite"
con <- DBI::dbConnect(RSQLite::SQLite(), fixture)
q <- DBI::dbQuoteString(con, "huelga")
sql <- dbplyr::sql(paste0(
  "SELECT i.*, bm25(fts_items) AS rank FROM fts_items JOIN items i ON i.rowid = fts_items.rowid ",
  "WHERE fts_items MATCH ", q, " ORDER BY rank"
))
t <- dplyr::tbl(con, sql)
cat("class:", paste(class(sql), collapse=","), "\n")
cat("tbl_vars:\n"); print(tryCatch(dplyr::tbl_vars(t), error = function(e) paste("ERR:", conditionMessage(e))))
cat("\ncollect:\n"); print(tryCatch(dplyr::collect(t), error = function(e) paste("ERR:", conditionMessage(e))))
cat("\nselect excludes embedding:\n")
s <- tryCatch(dplyr::select(t, -dplyr::any_of("embedding")), error = function(e) paste("ERR:", conditionMessage(e)))
print(tryCatch(dplyr::collect(s), error = function(e) paste("ERR:", conditionMessage(e))))
DBI::dbDisconnect(con)
