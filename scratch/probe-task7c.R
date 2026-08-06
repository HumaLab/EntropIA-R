suppressMessages({
  library(DBI)
  library(RSQLite)
})

probe <- function(p, label) {
  con <- dbConnect(SQLite(), p, flags = SQLITE_RO)
  dbExecute(con, "PRAGMA query_only = ON")
  cat("==", label, "==\n")
  jm <- tryCatch(dbGetQuery(con, "PRAGMA journal_mode")[[1]], error = function(e) paste("ERR:", conditionMessage(e)))
  cat("journal_mode:", jm, "\n")
  cat("wal sidecar:", file.exists(paste0(p, "-wal")), " shm sidecar:", file.exists(paste0(p, "-shm")), "\n")
  cat("path:", p, "\n")
  dbDisconnect(con)
}

probe("tests/testthat/fixtures/full.sqlite", "full fixture")
probe("tests/testthat/fixtures/mini.sqlite", "mini fixture")

if (file.exists("data-test/entropia.sqlite")) {
  p <- "data-test/entropia.sqlite"
  con <- dbConnect(SQLite(), p, flags = SQLITE_RO)
  dbExecute(con, "PRAGMA query_only = ON")
  cat("== real DB ==\n")
  cat("journal_mode:", dbGetQuery(con, "PRAGMA journal_mode")[[1]], "\n")
  cat("wal sidecar:", file.exists(paste0(p, "-wal")), " shm sidecar:", file.exists(paste0(p, "-shm")), "\n")
  # content hash attribute value
  dbDisconnect(con)
}

# empty DB: a scratch DB with no tables
tmp <- tempfile(fileext = ".sqlite")
con <- dbConnect(SQLite(), tmp)
dbDisconnect(con)
probe(tmp, "empty scratch (no tables)")

# Verify dbplyr/dplyr availability for tests
cat("\ndbplyr:", requireNamespace("dbplyr", quietly = TRUE), " dplyr:", requireNamespace("dplyr", quietly = TRUE), "\n")
