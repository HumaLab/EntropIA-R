suppressMessages({ devtools::load_all(".", quiet = TRUE) })

# Construct a malformed JSON string containing an invalid UTF-8 byte (0xE9).
bad <- rawToChar(as.raw(c(0x7b, 0x22, 0x61, 0x22, 0x3a, 0x20, 0xe9, 0x7d)))
cat("string bytes:", paste0(as.hexmode(as.integer(charToRaw(bad))), collapse = " "), "\n")

# It must fail jsonlite parsing
cond <- tryCatch(jsonlite::fromJSON(bad, simplifyVector = TRUE), error = function(e) e)
cat("is condition:", inherits(cond, "condition"), "\n")
cat("msg sanitized:", entropiaR:::ent_sanitize_msg(conditionMessage(cond)), "\n")

# ent_parse_json_col should warn (not crash) and yield NA
wl <- character()
res <- withCallingHandlers(
  entropiaR:::ent_parse_json_col(bad),
  warning = function(w) { wl <<- c(wl, class(w)[1]); invokeRestart("muffleWarning") }
)
cat("parse result:", res[[1]], "| is NA:", is.na(res[[1]]), "\n")
cat("warning classes:", paste(wl, collapse = ","), "\n")

# A valid cell alongside the invalid one still parses
wl2 <- character()
res2 <- withCallingHandlers(
  entropiaR:::ent_parse_json_col(c('{"ok": 1}', bad)),
  warning = function(w) { wl2 <<- c(wl2, class(w)[1]); invokeRestart("muffleWarning") }
)
cat("cell1 parsed:", res2[[1]]$ok, "| cell2 NA:", is.na(res2[[2]]), "\n")

# Direct helper checks
cat("sanitize NULL:", entropiaR:::ent_sanitize_msg(NULL), "\n")
cat("sanitize NA:", entropiaR:::ent_sanitize_msg(NA_character_), "\n")
cat("sanitize clean:", entropiaR:::ent_sanitize_msg("plain text"), "\n")
