pkgload::load_all("G:/EntropIA-Stack/EntropIA-R", quiet = TRUE)
Sys.setenv(NOT_CRAN = "true")
path <- ent_fixture("full")
con <- DBI::dbConnect(RSQLite::SQLite(), path)
ddl <- DBI::dbGetQuery(con, "SELECT name, sql FROM sqlite_master WHERE type = 'table' AND name IN ('items','transcriptions','llm_results','rag_messages')")
for (i in seq_len(nrow(ddl))) {
  cat("=== ", ddl$name[i], " ===\n")
  cat(substr(ddl$sql[i], 1, 600), "\n\n")
}
DBI::dbDisconnect(con)
