suppressPackageStartupMessages({
  library(devtools)
  library(dplyr)
})
load_all("G:/EntropIA-Stack/EntropIA-R", quiet = TRUE)

con <- entropia_connect("G:/EntropIA-Stack/EntropIA-R/tests/testthat/fixtures/full.sqlite")

cat("=== Filtered corpus (collections) plan ===\n")
t <- entropia_corpus(con, collections = "Collection One")
sql <- as.character(dbplyr::sql_render(t))
cat(sql, "\n")
print(DBI::dbGetQuery(con, paste0("EXPLAIN QUERY PLAN ", sql)))

cat("\n=== Filtered corpus (asset_types + collection) ===\n")
t2 <- entropia_corpus(con, collections = "Collection One", asset_types = "pdf")
print(DBI::dbGetQuery(con, paste0("EXPLAIN QUERY PLAN ", as.character(dbplyr::sql_render(t2)))))

cat("\n=== corpus filtered, no text ===\n")
t3 <- entropia_corpus(con, collections = "Collection One", text = FALSE)
print(DBI::dbGetQuery(con, paste0("EXPLAIN QUERY PLAN ", as.character(dbplyr::sql_render(t3)))))

cat("\n=== search plan detail strings ===\n")
s <- DBI::dbGetQuery(con, paste0("EXPLAIN QUERY PLAN ", as.character(dbplyr::sql_render(entropia_search(con, "huelga")))))
print(s$detail)

entropia_disconnect(con)
cat("DONE\n")
