suppressMessages({ devtools::load_all(".", quiet = TRUE) })
cat("locale:", Sys.getlocale(), "\n")
cat("native enc:", l10n_info()$`UTF-8`, "\n")

con <- entropia_connect("scratch/task31/real-smoke.sqlite")
raw <- DBI::dbGetQuery(con, "SELECT id, result FROM llm_results")
bad_id <- "llr-asset-981f3a0a-a205-4072-b263-56f938f94426-correct_ocr"
z <- raw$result[raw$id == bad_id]
cond <- tryCatch(jsonlite::fromJSON(z, simplifyVector = TRUE), error = function(e) e)
msg <- conditionMessage(cond)

cat("--- raw msg first 100 bytes ---\n")
cat(paste0(as.hexmode(charToRaw(substr(msg, 1, 100))), collapse = " "), "\n")

# Fix candidate 1: iconv replacement
msg2 <- iconv(msg, from = "UTF-8", to = "UTF-8", sub = "�")
cat("iconv replacement OK:", !is.na(msg2), "\n")
w1 <- tryCatch({ cli::ansi_strwrap(paste0("Malformed JSON, returning NA: ", msg2), width = 80); "ok" },
               error = function(e) conditionMessage(e))
cat("ansi_strwrap after iconv:", w1, "\n")

# Fix candidate 2: enc2utf8
msg3 <- enc2utf8(msg)
w2 <- tryCatch({ cli::ansi_strwrap(paste0("Malformed JSON, returning NA: ", msg3), width = 80); "ok" },
               error = function(e) conditionMessage(e))
cat("ansi_strwrap after enc2utf8:", w2, "\n")

# Fix candidate 3: truncate then iconv
msg4 <- iconv(substr(msg, 1, 120), from = "UTF-8", to = "UTF-8", sub = "�")
w3 <- tryCatch({ cli::ansi_strwrap(paste0("Malformed JSON, returning NA: ", msg4), width = 80); "ok" },
               error = function(e) conditionMessage(e))
cat("ansi_strwrap after truncate+iconv:", w3, "\n")

# Now test the full collect with a patched parse (via options? no — simulate)
# Confirm the full entropia_collect(entropia_llm_results(con)) works if we
# temporarily patch ent_parse_json_col to sanitize.
cat("\n--- full collect with default (expect crash) ---\n")
r <- tryCatch({
  withCallingHandlers(
    entropia_collect(entropia_llm_results(con)),
    warning = function(w) invokeRestart("muffleWarning")
  )
  "collect ok"
}, error = function(e) paste("collect ERROR:", substr(conditionMessage(e), 1, 80)))
cat(r, "\n")
entropia_disconnect(con)
