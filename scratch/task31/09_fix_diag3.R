suppressMessages({ devtools::load_all(".", quiet = TRUE) })
con <- entropia_connect("scratch/task31/real-smoke.sqlite")
raw <- DBI::dbGetQuery(con, "SELECT id, result FROM llm_results")

# Sanitizer helper exactly as proposed for ent_parse_json_col
ent_msg_sanitize <- function(m) {
  if (is.null(m) || length(m) == 0L || is.na(m)) return("<unreadable JSON>")
  out <- tryCatch(iconv(m, from = "UTF-8", to = "UTF-8", sub = "?"), error = function(e) NA_character_)
  if (is.na(out)) out <- "<unreadable JSON>"
  out
}

# Use cli interpolation (like the original) but on the sanitized value.
wr <- character()
zz <- withCallingHandlers(
  lapply(raw$result, function(s) {
    parsed <- tryCatch(jsonlite::fromJSON(s, simplifyVector = TRUE), error = function(e) e)
    if (inherits(parsed, "condition")) {
      safe <- ent_msg_sanitize(conditionMessage(parsed))
      cli::cli_warn("Malformed JSON, returning NA: {safe}", class = "entropia_warn_malformed_json")
      return(NA_character_)
    }
    parsed
  }),
  warning = function(w) { wr <<- c(wr, conditionMessage(w)); invokeRestart("muffleWarning") }
)
cat("lapply completed. warnings captured:", length(wr), "\n")
cat("NAs in result:", sum(is.na(zz)), "\n")
cat("first warning msg (50 chars):", substr(wr[1], 1, 50), "\n")
cat("any warning containing replacement marker:", any(grepl("\\?", wr)), "\n")

# Also verify the warning carries the right class
wl <- character()
withCallingHandlers(
  { safe <- ent_msg_sanitize(conditionMessage(
      tryCatch(jsonlite::fromJSON(raw$result[raw$id == "llr-asset-981f3a0a-a205-4072-b263-56f938f94426-correct_ocr"],
                                  simplifyVector = TRUE), error = function(e) e)))
    cli::cli_warn("Malformed JSON, returning NA: {safe}", class = "entropia_warn_malformed_json") },
  warning = function(w) { wl <<- c(wl, class(w)[1]); invokeRestart("muffleWarning") }
)
cat("warning class:", wl[1], "\n")
entropia_disconnect(con)
