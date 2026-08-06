sink("G:/EntropIA-Stack/EntropIA-R/scratch/loadseq.log")
cat("start\n")
for (p in c("cli", "DBI", "RSQLite", "dbplyr", "dplyr", "tibble", "rlang", "jsonlite", "tidyselect", "stringr", "digest", "methods", "lifecycle")) {
  ok <- tryCatch({ library(p, character.only = TRUE); "ok" }, error = function(e) paste("err", conditionMessage(e)))
  cat(p, ":", ok, "\n")
  flush.console()
}
cat("done\n")
sink()
