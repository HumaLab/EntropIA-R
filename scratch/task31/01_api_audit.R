# Task 31 audit 1: verify all Overview requirements implemented
# Audit the exported API against the plan's 10 capability groups.
suppressMessages({
  devtools::load_all(".", quiet = TRUE)
})

exports <- sort(getNamespaceExports("entropiaR"))

capabilities <- list(
  connection = c("entropia_connect", "entropia_disconnect", "entropia_schema_version",
                 "entropia_schema_info", "entropia_status", "entropia_validate",
                 "entropia_copy", "entropia_schema_compat"),
  entity_access = c("entropia_collections", "entropia_items", "entropia_assets",
                    "entropia_extractions", "entropia_transcriptions", "entropia_layouts",
                    "entropia_notes", "entropia_annotations", "entropia_entities",
                    "entropia_triples", "entropia_topics", "entropia_item_topics",
                    "entropia_llm_results", "entropia_rag_conversations",
                    "entropia_rag_messages", "entropia_embeddings", "entropia_chunks",
                    "entropia_search_index"),
  search = c("entropia_search"),
  collect_typing = c("entropia_collect", "entropia_datetime", "entropia_datetime_s",
                     "entropia_datetime_auto"),
  domain = c("entropia_corpus", "entropia_text", "entropia_metadata",
             "entropia_ocr_coverage", "entropia_metadata_coverage",
             "entropia_corpus_quality", "entropia_orphans"),
  research = c("entropia_entity_relations", "entropia_reconstruct_analysis",
               "entropia_conversation"),
  analysis = c("entropia_temporal_profile", "entropia_document_lengths",
               "entropia_entity_frequency", "entropia_topic_frequency",
               "entropia_compare_collections", "entropia_analysis_dataset"),
  viz = c("entropia_plot_coverage", "entropia_plot_temporal", "entropia_plot_entities"),
  export = c("entropia_export", "entropia_provenance", "entropia_write_provenance"),
  write_stubs = c("entropia_insert", "entropia_update", "entropia_upsert", "entropia_delete"),
  sync = c("entropia_sync_info", "entropia_sync_versions", "entropia_conflicts")
)

all_expected <- sort(unique(unlist(capabilities)))
missing <- setdiff(all_expected, exports)
extra <- setdiff(exports, all_expected)

cat("Total exports:", length(exports), "\n")
cat("Expected in plan API:", length(all_expected), "\n")
cat("MISSING from package:", if (length(missing)) paste(missing, collapse = ", ") else "none", "\n")
cat("Exported but not in plan capability list (review):\n")
print(extra)

# Per-group coverage
for (g in names(capabilities)) {
  have <- sum(capabilities[[g]] %in% exports)
  cat(sprintf("%-16s %d/%d\n", g, have, length(capabilities[[g]])))
}

if (length(missing) > 0) {
  quit(status = 1)
}
cat("\nAPI AUDIT: PASS\n")
