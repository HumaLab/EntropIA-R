# Probe fixtures + manifest to design Task 7 tests.
suppressMessages({
  library(DBI)
  library(RSQLite)
})

fixtures <- c(
  mini = "mini.sqlite",
  full = "full.sqlite",
  "legacy-pre0019" = "legacy-pre0019.sqlite",
  "legacy-seconds" = "legacy-seconds.sqlite",
  "unknown-version" = "unknown-version.sqlite"
)

for (nm in names(fixtures)) {
  p <- file.path("tests/testthat/fixtures", fixtures[[nm]])
  con <- dbConnect(SQLite(), p, flags = SQLITE_RO)
  cat("====", nm, "====", "\n")
  tabs <- dbGetQuery(con, "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name")$name
  # exclude FTS shadows
  tabs <- tabs[!grepl("_fts_(config|data|docsize|idx|content)$", tabs)]
  counts <- vapply(tabs, function(t) {
    tryCatch(as.integer(dbGetQuery(con, paste0("SELECT count(*) n FROM ", t))$n), error = function(e) NA_integer_)
  }, integer(1))
  cnt <- counts[!is.na(counts)]
  ord <- order(cnt, decreasing = TRUE)
  cat("top tables:", paste(names(cnt)[ord[1:min(8, length(cnt))]], cnt[ord[1:min(8, length(cnt))]], sep = "=", collapse = ", "), "\n")
  if (dbExistsTable(con, "sync_meta")) {
    sm <- dbGetQuery(con, "SELECT * FROM sync_meta")
    cat("sync_meta cols:", paste(names(sm), collapse = ","), "\n")
    cat("sync_meta nrow:", nrow(sm), "\n")
    if (nrow(sm)) {
      cat("  device_id:", sm$device_id[1], "\n")
      cat("  last_sync_at raw:", sm$last_sync_at[1], " class:", class(sm$last_sync_at[1]), "\n")
      cat("  capture_enabled:", sm$capture_enabled[1], "\n")
      cat("  triggers_version:", if ("triggers_version" %in% names(sm)) sm$triggers_version[1] else "NA", "\n")
    }
  }
  if (dbExistsTable(con, "_migrations")) {
    cat("mig max:", dbGetQuery(con, "SELECT MAX(name) v FROM _migrations")$v, "\n")
  }
  dbDisconnect(con)
}

# empty DB probe: just _migrations
tmp <- tempfile(fileext = ".sqlite")
con <- dbConnect(SQLite(), tmp)
dbExecute(con, "CREATE TABLE _migrations (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE, applied_at INTEGER NOT NULL)")
dbExecute(con, "INSERT INTO _migrations (name, applied_at) VALUES ('0001_initial', 1768478400)")
cat("===empty (migrations only)===\n")
cat("items exists:", dbExistsTable(con, "items"), "\n")
dbDisconnect(con)

# mini fixture table list
p <- file.path("tests/testthat/fixtures", "mini.sqlite")
con <- dbConnect(SQLite(), p, flags = SQLITE_RO)
cat("===mini tables===\n")
print(dbGetQuery(con, "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name")$name)
dbDisconnect(con)

# manifest structure
mf <- jsonlite::fromJSON("inst/schemas/manifest.json", simplifyVector = FALSE)
cat("===manifest===\n")
cat("head:", mf$schema_head, "\n")
cat("tables:", paste(names(mf$tables), collapse = ", "), "\n")
cat("n tables:", length(mf$tables), "\n")
