suppressMessages({
  library(DBI)
  library(RSQLite)
})

con <- dbConnect(SQLite(), "tests/testthat/fixtures/full.sqlite", flags = SQLITE_RO)
cat("=== full.sqlite sync_meta content ===\n")
print(dbGetQuery(con, "SELECT * FROM sync_meta"))
cat("\n=== full.sqlite app_settings content ===\n")
print(dbGetQuery(con, "SELECT * FROM app_settings"))
dbDisconnect(con)

# real DB probe (read-only)
cat("\n=== data-test/entropia.sqlite ===\n")
if (file.exists("data-test/entropia.sqlite")) {
  con2 <- dbConnect(SQLite(), "data-test/entropia.sqlite", flags = SQLITE_RO)
  tabs <- dbGetQuery(con2, "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name")$name
  tabs <- tabs[!grepl("_fts_(config|data|docsize|idx|content)$", tabs)]
  cat("n tables:", length(tabs), "\n")
  if (dbExistsTable(con2, "sync_meta")) {
    cat("sync_meta cols:", paste(names(dbGetQuery(con2, "SELECT * FROM sync_meta LIMIT 1")), collapse = ","), "\n")
    sm <- dbGetQuery(con2, "SELECT * FROM sync_meta LIMIT 20")
    print(utils::head(sm, 20))
  }
  counts <- vapply(tabs, function(t) {
    tryCatch(as.integer(dbGetQuery(con2, paste0("SELECT count(*) n FROM ", t))$n), error = function(e) NA_integer_)
  }, integer(1))
  cnt <- counts[!is.na(counts)]
  ord <- order(cnt, decreasing = TRUE)
  cat("\nreal top counts:\n")
  print(cnt[ord])
  dbDisconnect(con2)
}
