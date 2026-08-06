suppressMessages({
  library(DBI)
  library(RSQLite)
})

# corrupt fixture
p <- "tests/testthat/fixtures/corrupt.sqlite"
con <- tryCatch(dbConnect(SQLite(), p, flags = SQLITE_RO), error = function(e) { cat("connect err:", conditionMessage(e), "\n"); NULL })
if (!is.null(con)) {
  cat("connected to corrupt; slots:", paste(methods::slotNames(con), collapse = ","), "\n")
  cat("dbname slot:", con@dbname, "\n")
  r <- tryCatch(dbGetQuery(con, "SELECT name FROM sqlite_master"), error = function(e) conditionMessage(e))
  if (is.character(r) && length(r) == 1) cat("sqlite_master err:", substr(r, 1, 100), "\n") else print(head(r))
  r2 <- tryCatch(dbGetQuery(con, "SELECT count(*) n FROM items"), error = function(e) conditionMessage(e))
  if (is.character(r2) && length(r2) == 1) cat("count items err:", substr(r2, 1, 100), "\n") else print(r2)
  dbDisconnect(con)
}

# dbname on a normal fixture + :memory:
con2 <- dbConnect(SQLite(), "tests/testthat/fixtures/mini.sqlite", flags = SQLITE_RO)
cat("\nmini dbname slot:", con2@dbname, "\n")
dbDisconnect(con2)
con3 <- dbConnect(SQLite(), ":memory:")
cat("memory dbname slot:", con3@dbname, "\n")
dbDisconnect(con3)

# does PRAGMA journal_mode work under query_only?
con4 <- dbConnect(SQLite(), "tests/testthat/fixtures/full.sqlite", flags = SQLITE_RO)
dbExecute(con4, "PRAGMA query_only = ON")
cat("\njournal_mode under query_only:", dbGetQuery(con4, "PRAGMA journal_mode")[[1]], "\n")
dbDisconnect(con4)
