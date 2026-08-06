suppressMessages({ devtools::load_all(".", quiet = TRUE) })
con <- entropia_connect("scratch/task31/real-smoke.sqlite")
raw <- DBI::dbGetQuery(con, "SELECT id, result FROM llm_results")

fails <- vapply(raw$result, function(z) {
  inherits(tryCatch(jsonlite::fromJSON(z, simplifyVector = TRUE), error = function(e) e), "condition")
}, logical(1))
bad_ids <- raw$id[fails]
cat("malformed count:", length(bad_ids), "\n")

# For each malformed result, build the cli message and see if ansi_strwrap breaks.
for (i in seq_along(bad_ids)) {
  z <- raw$result[raw$id == bad_ids[i]]
  cond <- tryCatch(jsonlite::fromJSON(z, simplifyVector = TRUE), error = function(e) e)
  msg <- paste0("Malformed JSON, returning NA: ", conditionMessage(cond))
  # Directly test the wrap primitive
  w <- tryCatch({
    cli::ansi_strwrap(msg, width = 80)
    "ok"
  }, error = function(e) conditionMessage(e))
  if (w != "ok") {
    cat("BREAKING id:", bad_ids[i], "\n")
    cat("nchar width NA:", is.na(nchar(msg, type = "width")), "\n")
    cat("msg bytes (first 200):", paste0(as.hexmode(charToRaw(substr(msg, 1, 200))), collapse = " "), "\n")
    cat("--- msg (first 300) ---\n")
    cat(substr(msg, 1, 300), "\n---\n")
    break
  }
  if (i == 1 || i == length(bad_ids)) cat("tested", i, "of", length(bad_ids), "ok\n")
  if (i == 100) cat("first 100 all ok\n")
}
entropia_disconnect(con)
