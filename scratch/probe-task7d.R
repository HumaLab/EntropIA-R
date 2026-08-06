mf <- jsonlite::fromJSON("inst/schemas/manifest.json", simplifyVector = FALSE)
cat("schema_head:", mf$schema_head, "\n")
for (t in c("collections", "items", "assets", "extractions", "transcriptions", "entities", "llm_results", "sync_meta")) {
  e <- mf$tables[[t]]
  cat("\n##", t, " table min_version:", if (is.null(e$min_version)) "NULL" else e$min_version, "\n")
  for (c in names(e$columns)) {
    mc <- e$columns[[c]]
    cat("  ", c, "| type=", mc$type,
        "| required=", isTRUE(mc$required),
        "| min_version=", if (is.null(mc$min_version)) "NULL" else mc$min_version,
        "\n")
  }
}
