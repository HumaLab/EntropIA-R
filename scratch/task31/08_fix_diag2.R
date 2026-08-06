suppressMessages({ devtools::load_all(".", quiet = TRUE) })
con <- entropia_connect("scratch/task31/real-smoke.sqlite")
raw <- DBI::dbGetQuery(con, "SELECT id, result FROM llm_results")
bad_id <- "llr-asset-981f3a0a-a205-4072-b263-56f938f94426-correct_ocr"
z <- raw$result[raw$id == bad_id]
cond <- tryCatch(jsonlite::fromJSON(z, simplifyVector = TRUE), error = function(e) e)
msg <- conditionMessage(cond)

cat("Encoding mark:", Encoding(msg), "\n")

safe <- iconv(msg, from = "UTF-8", to = "UTF-8", sub = "?")
cat("iconv returned NA?", is.na(safe), "\n")
cat("Encoding after iconv:", Encoding(safe), "\n")
cat("nchar width:", nchar(safe, type = "width"), "\n")

w1 <- tryCatch({
  cli::ansi_strwrap(paste0("Malformed JSON, returning NA: ", safe), width = 80)
  "ok"
}, error = function(e) paste("ERROR:", conditionMessage(e)))
cat("ansi_strwrap after iconv:", w1, "\n")

# Also test the fallback when iconv fails entirely
safe2 <- tryCatch(
  iconv(msg, from = "UTF-8", to = "UTF-8", sub = "?"),
  error = function(e) "<unreadable error message>"
)
if (is.na(safe2)) safe2 <- "<unreadable error message>"
w2 <- tryCatch({
  cli::ansi_strwrap(paste0("Malformed JSON, returning NA: ", safe2), width = 80)
  "ok"
}, error = function(e) paste("ERROR:", conditionMessage(e)))
cat("ansi_strwrap after guarded iconv:", w2, "\n")

# Full collect with patched parse via trace? Just verify the warning triggers
# cli safely using the sanitized message.
wr <- character()
out <- withCallingHandlers(
  {
    # simulate what ent_parse_json_col does, sanitized
    zz <- lapply(raw$result, function(s) {
      parsed <- tryCatch(jsonlite::fromJSON(s, simplifyVector = TRUE), error = function(e) e)
      if (inherits(parsed, "condition")) {
        m <- conditionMessage(parsed)
        m <- tryCatch(iconv(m, from = "UTF-8", to = "UTF-8", sub = "?"),
                      error = function(e) "<unreadable>")
        if (is.na(m)) m <- "<unreadable>"
        cli::cli_warn(paste0("Malformed JSON, returning NA: ", m), class = "entropia_warn_malformed_json")
        return(NA_character_)
      }
      parsed
    })
    "simulated collect ok"
  },
  warning = function(w) { wr <<- c(wr, conditionMessage(w)); invokeRestart("muffleWarning") }
)
cat(out, "\n")
cat("warnings captured:", length(wr), "\n")
entropia_disconnect(con)
