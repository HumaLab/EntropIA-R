suppressMessages({ devtools::load_all(".", quiet = TRUE) })
con <- entropia_connect("scratch/task31/real-smoke.sqlite")

# Pull raw result values and find the malformed ones
raw <- DBI::dbGetQuery(con, "SELECT id, result FROM llm_results")
cat("total llm_results:", nrow(raw), "\n")
cat("NA results:", sum(is.na(raw$result)), "\n")

# How many fail jsonlite::fromJSON?
fails <- vapply(raw$result, function(z) {
  inherits(tryCatch(jsonlite::fromJSON(z, simplifyVector = TRUE), error = function(e) e), "condition")
}, logical(1))
cat("malformed:", sum(fails, na.rm = TRUE), "\n")

bad <- raw$result[which(fails)][1]
cat("\n--- first malformed result (first 200 chars) ---\n")
cat(substr(bad, 1, 200), "\n")
cat("\n--- condition message (first 300 chars) ---\n")
cond <- tryCatch(jsonlite::fromJSON(bad, simplifyVector = TRUE), error = function(e) e)
msg <- conditionMessage(cond)
cat(substr(msg, 1, 300), "\n")
cat("\n--- encoding of message ---\n")
cat("Encoding:", Encoding(msg), "\n")
cat("nchar (chars):", nchar(msg, type = "chars"), "\n")
cat("nchar (width) NA?:", is.na(nchar(msg, type = "width")), "\n")

# Does cli_warn crash on this message?
cat("\n--- testing cli::cli_warn on the raw condition message ---\n")
res <- tryCatch({
  cli::cli_warn("Malformed JSON, returning NA: {conditionMessage(cond)}", class = "test_warn")
  "cli_warn worked"
}, error = function(e) paste("cli_warn ERROR:", conditionMessage(e)))
cat(res, "\n")

# Test with cli message truncation safeguard
cat("\n--- testing with substr to 120 chars ---\n")
res2 <- tryCatch({
  cli::cli_warn("Malformed JSON, returning NA: {substr(conditionMessage(cond), 1, 120)}", class = "test_warn")
  "cli_warn worked (truncated)"
}, error = function(e) paste("cli_warn ERROR:", conditionMessage(e)))
cat(res2, "\n")

entropia_disconnect(con)
