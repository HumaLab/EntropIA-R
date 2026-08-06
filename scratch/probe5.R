suppressMessages(devtools::load_all("G:/EntropIA-Stack/EntropIA-R", quiet = TRUE))
src <- "G:/EntropIA-Stack/EntropIA-R/data-test/entropia.sqlite"
if (!file.exists(src)) { cat("NO REAL DB\n"); quit(status = 0) }
# WAL-aware snapshot copy, as Task 4's entropia_copy() does.
tmp <- tempfile(fileext = ".sqlite")
con0 <- DBI::dbConnect(RSQLite::SQLite(), src, flags = RSQLite::SQLITE_RO)
DBI::dbExecute(con0, "PRAGMA query_only = OFF")
DBI::dbExecute(con0, sprintf("VACUUM INTO '%s'", gsub("'", "''", tmp)))
DBI::dbDisconnect(con0)

con <- entropiaR::entropia_connect(tmp, validate = FALSE)
res <- entropiaR::entropia_search(con, "huelga", limit = 5)
out <- dplyr::collect(res)
cat("items search 'huelga' rows:", nrow(out), "\n")
print(out[, c("id", "title")])
cat("\nchunks search 'huelga' rows:", nrow(dplyr::collect(entropiaR::entropia_search(con, "huelga", index = "chunks", limit = 5))), "\n")
entropiaR::entropia_disconnect(con)
