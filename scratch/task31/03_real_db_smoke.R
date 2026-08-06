# Task 31 audit 3b: real-DB smoke test (assert-only, on a VACUUM INTO copy —
# never touches data-test/entropia.sqlite)
suppressMessages({
  devtools::load_all(".", quiet = TRUE)
})
library(dplyr)

db <- "scratch/task31/real-smoke.sqlite"
con <- entropia_connect(db)
fail <- function(msg) { cat("SMOKE FAIL:", msg, "\n"); quit(status = 1) }
chk <- function(label, cond, detail = "") {
  cat(sprintf("%-55s %s\n", label, if (isTRUE(cond)) "ok" else paste("FAIL", detail)))
  if (!isTRUE(cond)) quit(status = 1)
}

# 1. connection + schema version
chk("connect read-only", inherits(con, "entropia_conn"))
chk("schema_version", entropia_schema_version(con) == "0029_rag_chunks",
    entropia_schema_version(con))
info <- entropia_schema_info(con)
chk("schema_info tables >= 29", nrow(info) >= 29, nrow(info))

# 2. reference row counts
n_coll <- entropia_collect(entropia_collections(con)) %>% nrow()
n_items <- entropia_collect(entropia_items(con)) %>% nrow()
n_assets <- entropia_collect(entropia_assets(con)) %>% nrow()
chk("collections == 17", n_coll == 17, n_coll)
chk("items == 2393", n_items == 2393, n_items)
chk("assets == 2477", n_assets == 2477, n_assets)

# 3. entities soft-delete
n_ent <- entropia_collect(entropia_entities(con)) %>% nrow()
n_ent_all <- entropia_collect(entropia_entities(con, include_deleted = TRUE)) %>% nrow()
chk("entities default 1328", n_ent == 1328, n_ent)
chk("entities include_deleted 1339", n_ent_all == 1339, n_ent_all)

# 4. triples / llm_results / chunks / rag_messages
chk("triples == 700", entropia_collect(entropia_triples(con)) %>% nrow() == 700)
chk("llm_results == 147", entropia_collect(entropia_llm_results(con)) %>% nrow() == 147)
chk("chunks == 1648", entropia_collect(entropia_chunks(con)) %>% nrow() == 1648)
chk("rag_messages == 102", entropia_collect(entropia_rag_messages(con)) %>% nrow() == 102)
chk("chunks no BLOB by default",
    !("embedding" %in% colnames(entropia_collect(entropia_chunks(con)))))

# 5. corpus
cor <- entropia_collect(entropia_corpus(con))
chk("corpus rows == 2477", nrow(cor) == 2477, nrow(cor))
chk("corpus has text", "text" %in% colnames(cor))
chk("corpus has collection_name", "collection_name" %in% colnames(cor))
chk("corpus no BLOB", !("embedding" %in% colnames(cor)))

# 6. search
res <- entropia_search(con, "huelga", limit = 5) %>% entropia_collect()
chk("search returns rows", nrow(res) >= 1, nrow(res))

# 7. text markers
txt <- entropia_collect(entropia_text(con))
markers <- sum(grepl("!\\[\\]\\(page=", txt$text, perl = TRUE), na.rm = TRUE)
chk("no markers after strip", markers == 0, markers)

# 8. validate / orphans
v <- entropia_validate(con)
chk("validate zero errors", sum(v$severity == "error") == 0,
    paste(sum(v$severity == "error"), "errors"))
o <- entropia_orphans(con)
chk("orphans zero rows", nrow(o) == 0, nrow(o))

# 9. sync_info no secrets
si <- entropia_sync_info(con)
chk("sync_info has account_email", "account_email" %in% names(si))
leaks <- grep("api_key", names(si), value = TRUE, ignore.case = TRUE)
chk("no api_key leak in sync_info", length(leaks) == 0, paste(leaks, collapse = ","))

# 10. export smoke to temp csv
tmp <- tempfile(fileext = ".csv")
entropia_export(entropia_corpus(con), tmp)
exp <- read.csv(tmp, stringsAsFactors = FALSE)
chk("export corpus 2477 rows", nrow(exp) == 2477, nrow(exp))
unlink(tmp)

# 11. read-only enforced
ro_ok <- tryCatch({ DBI::dbWriteTable(con, "t", data.frame(a = 1)); FALSE },
                  error = function(e) TRUE)
chk("read-only enforced", ro_ok)

entropia_disconnect(con)
cat("\nREAL-DB SMOKE: PASS\n")
