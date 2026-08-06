suppressMessages({
  library(jsonlite)
  library(rlang)
  library(dplyr)
  library(tibble)
})
# as_label on a quosure
q <- quo(asset_type == "image")
cat("as_label:", rlang::as_label(q), "\n")
# toJSON with NULL and empty char vector
prov <- list(name = NULL, filters = "asset_type == \"image\"", pkg = "0.0.0.9000", built = "2026-08-06T12:00:00.123Z")
cat(toJSON(unclass(prov), auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null"), "\n")
# empty filters -> JSON
prov2 <- list(filters = character(0))
cat(toJSON(prov2, auto_unbox = TRUE), "\n")
# glimpse generic check
cat("glimpse generic:", is.function(dplyr::glimpse), "\n")
# arrange on asset_id
df <- tibble(asset_id = c("b", "a"), x = c(1, 2))
cat("arrange:", paste(dplyr::arrange(df, .data$asset_id)$asset_id, collapse = ","), "\n")
# round trip
rt <- fromJSON(toJSON(unclass(prov), auto_unbox = TRUE, null = "null", na = "null"))
cat("rt name is NULL:", is.null(rt$name), "| filters:", rt$filters, "\n")
cat("SANE\n")
