suppressMessages({
  library(DBI)
  library(RSQLite)
})
# Replicate ent_tables + ent_current_version + ent_min_version_applies logic.
et <- function(con) {
  tabs <- dbGetQuery(con, "SELECT name, sql FROM sqlite_master WHERE type = 'table'")
  virtual <- tabs$name[grepl("^CREATE VIRTUAL TABLE", tabs$sql)]
  shadow <- unlist(lapply(virtual, function(v) paste0(v, c("_config", "_data", "_docsize", "_idx", "_content"))), use.names = FALSE)
  sort(tabs$name[!(startsWith(tabs$name, "sqlite_") | tabs$name %in% shadow)])
}
ver_of <- function(con) {
  if (!dbExistsTable(con, "_migrations")) return(NA_character_)
  dbGetQuery(con, "SELECT MAX(name) v FROM _migrations")$v
}
mva <- function(min_version, ver) {
  if (is.null(min_version) || is.na(min_version)) return(TRUE)
  if (is.null(ver) || is.na(ver)) return(NA)
  ver >= min_version
}
mf <- jsonlite::fromJSON("inst/schemas/manifest.json", simplifyVector = FALSE)

for (nm in c("mini", "full", "legacy-pre0019", "legacy-seconds", "unknown-version")) {
  p <- file.path("tests/testthat/fixtures", paste0(nm, if (nm == "mini") ".sqlite" else if (nm == "unknown-version") ".sqlite" else paste0(nm, ".sqlite")))
  p <- switch(nm, mini = "tests/testthat/fixtures/mini.sqlite", full = "tests/testthat/fixtures/full.sqlite",
              "legacy-pre0019" = "tests/testthat/fixtures/legacy-pre0019.sqlite",
              "legacy-seconds" = "tests/testthat/fixtures/legacy-seconds.sqlite",
              "unknown-version" = "tests/testthat/fixtures/unknown-version.sqlite")
  con <- dbConnect(SQLite(), p, flags = SQLITE_RO)
  lt <- et(con); ver <- ver_of(con)
  missing_tables <- character()
  for (t in names(mf$tables)) {
    if (t %in% lt) next
    exp <- mva(mf$tables[[t]]$min_version %||% NULL, ver)
    if (isTRUE(exp) || is.na(exp)) missing_tables <- c(missing_tables, t)
  }
  cat(nm, "| ver:", ver, "| missing tables:", paste(missing_tables, collapse = ", "), "\n")
  dbDisconnect(con)
}
