## Probe RSQLite behaviors needed for entropia_connect design.
fixtures <- file.path("tests", "testthat", "fixtures")

probe <- function(label, expr) {
  cat("---", label, "---\n")
  out <- tryCatch(
    {
      suppressWarnings(force(expr))
      "OK (no error)"
    },
    error = function(e) paste0("ERROR [", class(e)[1], "]: ", conditionMessage(e)),
    warning = function(w) paste0("WARNING: ", conditionMessage(w))
  )
  cat(out, "\n\n")
}

# 1. corrupt fixture: connect + first query
probe("corrupt: connect", {
  con <- DBI::dbConnect(RSQLite::SQLite(), file.path(fixtures, "corrupt.sqlite"),
                        flags = RSQLite::SQLITE_RO)
  on.exit(DBI::dbDisconnect(con))
  DBI::dbGetQuery(con, "SELECT name FROM sqlite_master LIMIT 1")
})

# 2. notsqlite fixture
probe("notsqlite: connect+query", {
  con <- DBI::dbConnect(RSQLite::SQLite(), file.path(fixtures, "notsqlite.txt"),
                        flags = RSQLite::SQLITE_RO)
  on.exit(DBI::dbDisconnect(con))
  DBI::dbGetQuery(con, "SELECT name FROM sqlite_master LIMIT 1")
})

# 3. :memory: with RO flag
probe(":memory: with SQLITE_RO", {
  con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:", flags = RSQLite::SQLITE_RO)
  on.exit(DBI::dbDisconnect(con))
  DBI::dbGetQuery(con, "SELECT 1 AS x")
})

# 4. query_only pragma on RO connection + write attempt
tmp <- tempfile(fileext = ".sqlite")
file.copy(file.path(fixtures, "mini.sqlite"), tmp)
probe("query_only write attempt", {
  con <- DBI::dbConnect(RSQLite::SQLite(), tmp, flags = RSQLite::SQLITE_RO)
  on.exit(DBI::dbDisconnect(con))
  DBI::dbExecute(con, "PRAGMA query_only = ON")
  DBI::dbGetQuery(con, "PRAGMA query_only")
  DBI::dbExecute(con, "INSERT INTO collections (id, name, created_at, updated_at)
                   VALUES ('x', 'x', 1, 1)")
})

# 5. dbWriteTable error message on RO
probe("dbWriteTable on RO", {
  con <- DBI::dbConnect(RSQLite::SQLite(), tmp, flags = RSQLite::SQLITE_RO)
  on.exit(DBI::dbDisconnect(con))
  DBI::dbWriteTable(con, "t_new", data.frame(a = 1))
})

# 6. locked DB: exclusive transaction in A, RO read in B
probe("locked: RO read under EXCLUSIVE", {
  a <- DBI::dbConnect(RSQLite::SQLite(), tmp)
  on.exit(DBI::dbDisconnect(a))
  DBI::dbExecute(a, "BEGIN EXCLUSIVE")
  b <- DBI::dbConnect(RSQLite::SQLite(), tmp, flags = RSQLite::SQLITE_RO)
  on.exit(DBI::dbDisconnect(b), add = TRUE)
  DBI::dbGetQuery(b, "SELECT name FROM sqlite_master LIMIT 1")
})

# 7. PRAGMA query_only on RW connection blocks writes?
probe("query_only on RW connection", {
  tmp2 <- tempfile(fileext = ".sqlite")
  file.copy(file.path(fixtures, "mini.sqlite"), tmp2)
  con <- DBI::dbConnect(RSQLite::SQLite(), tmp2)
  on.exit({DBI::dbDisconnect(con); unlink(tmp2)})
  DBI::dbExecute(con, "PRAGMA query_only = ON")
  DBI::dbExecute(con, "INSERT INTO collections (id, name, created_at, updated_at)
                   VALUES ('x', 'x', 1, 1)")
})

# 8. VACUUM INTO from a read-only connection
probe("VACUUM INTO from RO con", {
  dest <- tempfile(fileext = ".sqlite")
  con <- DBI::dbConnect(RSQLite::SQLite(), tmp, flags = RSQLite::SQLITE_RO)
  on.exit({DBI::dbDisconnect(con); unlink(dest)})
  DBI::dbExecute(con, sprintf("VACUUM INTO '%s'", dest))
  chk <- DBI::dbConnect(RSQLite::SQLite(), dest, flags = RSQLite::SQLITE_RO)
  on.exit(DBI::dbDisconnect(chk), add = TRUE)
  print(DBI::dbGetQuery(chk, "SELECT COUNT(*) AS n FROM collections"))
})

# 9. WAL: does -wal exist while a RW connection with inserts is open?
probe("WAL sidecars while writer open", {
  tmpw <- tempfile(fileext = ".sqlite")
  file.copy(file.path(fixtures, "mini.sqlite"), tmpw)
  a <- DBI::dbConnect(RSQLite::SQLite(), tmpw)
  on.exit({DBI::dbDisconnect(a); unlink(c(tmpw, paste0(tmpw, "-wal"), paste0(tmpw, "-shm")))})
  print(DBI::dbGetQuery(a, "PRAGMA journal_mode=WAL"))
  DBI::dbExecute(a, "INSERT INTO collections (id, name, created_at, updated_at)
                   VALUES ('wal-c', 'wal', 1, 1)")
  cat("wal exists:", file.exists(paste0(tmpw, "-wal")), "\n")
  cat("shm exists:", file.exists(paste0(tmpw, "-shm")), "\n")
  # RO reader + VACUUM INTO sees the committed row
  dest <- tempfile(fileext = ".sqlite")
  b <- DBI::dbConnect(RSQLite::SQLite(), tmpw, flags = RSQLite::SQLITE_RO)
  on.exit({DBI::dbDisconnect(b); unlink(dest)}, add = TRUE)
  DBI::dbExecute(b, sprintf("VACUUM INTO '%s'", dest))
  c2 <- DBI::dbConnect(RSQLite::SQLite(), dest, flags = RSQLite::SQLITE_RO)
  on.exit(DBI::dbDisconnect(c2), add = TRUE)
  print(DBI::dbGetQuery(c2, "SELECT COUNT(*) AS n FROM collections"))
})

unlink(tmp)
cat("probes done\n")
