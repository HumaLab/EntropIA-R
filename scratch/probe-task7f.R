suppressMessages({
  library(DBI)
  library(RSQLite)
})
p <- tempfile(fileext = ".sqlite")
db1 <- dbConnect(SQLite(), p)
dbExecute(db1, "PRAGMA journal_mode = WAL")
dbExecute(db1, "CREATE TABLE t (x INTEGER)")
dbExecute(db1, "INSERT INTO t VALUES (1)")
cat("journal_mode (writer):", dbGetQuery(db1, "PRAGMA journal_mode")[[1]], "\n")
cat("sidecars exist:", file.exists(paste0(p, "-wal")), file.exists(paste0(p, "-shm")), "\n")

# second read-only connection while writer holds WAL
r <- tryCatch({
  con <- dbConnect(SQLite(), p, flags = SQLITE_RO)
  dbExecute(con, "PRAGMA query_only = ON")
  jm <- dbGetQuery(con, "PRAGMA journal_mode")[[1]]
  n <- dbGetQuery(con, "SELECT count(*) n FROM t")$n
  dbDisconnect(con)
  list(ok = TRUE, jm = jm, n = n)
}, error = function(e) list(ok = FALSE, err = conditionMessage(e)))
cat("reader result:", if (r$ok) paste("OK jm=", r$jm, "n=", r$n) else paste("ERR:", r$err), "\n")
dbDisconnect(db1)
cat("after writer close, sidecars:", file.exists(paste0(p, "-wal")), file.exists(paste0(p, "-shm")), "\n")
