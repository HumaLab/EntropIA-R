# Package index

## Connection & administration

Open and close read-only connections to an EntropIA SQLite database,
snapshot it, and read the schema version and compatibility state.

- [`entropia_connect()`](https://humalab.github.io/EntropIA-R/reference/entropia_connect.md)
  : Connect to an EntropIA SQLite database (read-only)
- [`entropia_disconnect()`](https://humalab.github.io/EntropIA-R/reference/entropia_disconnect.md)
  : Close an EntropIA connection
- [`entropia_copy()`](https://humalab.github.io/EntropIA-R/reference/entropia_copy.md)
  : Snapshot a database to a new file (WAL-aware)
- [`entropia_conn-class`](https://humalab.github.io/EntropIA-R/reference/entropia_conn-class.md)
  [`entropia_conn`](https://humalab.github.io/EntropIA-R/reference/entropia_conn-class.md)
  : entropia_conn class
- [`entropia_schema_version()`](https://humalab.github.io/EntropIA-R/reference/entropia_schema_version.md)
  : Schema version of an EntropIA database
- [`entropia_schema_info()`](https://humalab.github.io/EntropIA-R/reference/entropia_schema_info.md)
  : Tables, columns and typed contract of an EntropIA database
- [`entropia_schema_compat()`](https://humalab.github.io/EntropIA-R/reference/entropia_schema_compat.md)
  : Schema compatibility status of an EntropIA database

## Entity access

One lazy `tbl_sql` accessor per readable table. Compose with
dplyr/dbplyr; materialise with
[`entropia_collect()`](https://humalab.github.io/EntropIA-R/reference/entropia_collect.md).

- [`entropia_collections()`](https://humalab.github.io/EntropIA-R/reference/entropia_collections.md)
  : Collections (lazy)
- [`entropia_items()`](https://humalab.github.io/EntropIA-R/reference/entropia_items.md)
  : Items (lazy)
- [`entropia_assets()`](https://humalab.github.io/EntropIA-R/reference/entropia_assets.md)
  : Assets (lazy)
- [`entropia_extractions()`](https://humalab.github.io/EntropIA-R/reference/entropia_extractions.md)
  : Extractions (lazy)
- [`entropia_transcriptions()`](https://humalab.github.io/EntropIA-R/reference/entropia_transcriptions.md)
  : Transcriptions (lazy)
- [`entropia_layouts()`](https://humalab.github.io/EntropIA-R/reference/entropia_layouts.md)
  : Layouts (lazy)
- [`entropia_notes()`](https://humalab.github.io/EntropIA-R/reference/entropia_notes.md)
  : Notes (lazy)
- [`entropia_annotations()`](https://humalab.github.io/EntropIA-R/reference/entropia_annotations.md)
  : Annotations (lazy)
- [`entropia_entities()`](https://humalab.github.io/EntropIA-R/reference/entropia_entities.md)
  : Entities (lazy)
- [`entropia_triples()`](https://humalab.github.io/EntropIA-R/reference/entropia_triples.md)
  : Triples (lazy)
- [`entropia_topics()`](https://humalab.github.io/EntropIA-R/reference/entropia_topics.md)
  : Topics (lazy)
- [`entropia_item_topics()`](https://humalab.github.io/EntropIA-R/reference/entropia_item_topics.md)
  : Item-topic links (lazy)
- [`entropia_llm_results()`](https://humalab.github.io/EntropIA-R/reference/entropia_llm_results.md)
  : LLM results (lazy)
- [`entropia_rag_conversations()`](https://humalab.github.io/EntropIA-R/reference/entropia_rag_conversations.md)
  : RAG conversations (lazy)
- [`entropia_rag_messages()`](https://humalab.github.io/EntropIA-R/reference/entropia_rag_messages.md)
  : RAG messages (lazy)
- [`entropia_embeddings()`](https://humalab.github.io/EntropIA-R/reference/entropia_embeddings.md)
  : Asset embedding vectors (lazy)
- [`entropia_chunks()`](https://humalab.github.io/EntropIA-R/reference/entropia_chunks.md)
  : RAG chunks (lazy)
- [`entropia_search_index()`](https://humalab.github.io/EntropIA-R/reference/entropia_search_index.md)
  : Items full-text index (lazy, raw)

## Search

Parameter-safe FTS5 full-text search over the items and chunk indexes.

- [`entropia_search()`](https://humalab.github.io/EntropIA-R/reference/entropia_search.md)
  : Search the full-text index

## Collection & typing

Materialise a lazy query with the column contract applied, and the pure
timestamp-conversion helpers.

- [`entropia_collect()`](https://humalab.github.io/EntropIA-R/reference/entropia_collect.md)
  : Collect and apply the column contract

- [`entropia_datetime()`](https://humalab.github.io/EntropIA-R/reference/entropia_datetime.md)
  :

  Convert epoch-millisecond timestamps to `POSIXct`

- [`entropia_datetime_s()`](https://humalab.github.io/EntropIA-R/reference/entropia_datetime_s.md)
  :

  Convert epoch-second timestamps to `POSIXct`

- [`entropia_datetime_auto()`](https://humalab.github.io/EntropIA-R/reference/entropia_datetime_auto.md)
  :

  Convert timestamps to `POSIXct` with a magnitude guard

## Domain layer

High-level, research-oriented views over the corpus: joined
items/assets/ collections with best text, parsed metadata, and text
helpers.

- [`entropia_corpus()`](https://humalab.github.io/EntropIA-R/reference/entropia_corpus.md)
  : Corpus (lazy)
- [`entropia_text()`](https://humalab.github.io/EntropIA-R/reference/entropia_text.md)
  : Per-asset best text (lazy)
- [`entropia_metadata()`](https://humalab.github.io/EntropIA-R/reference/entropia_metadata.md)
  : Item metadata (parsed)

## Corpus quality & diagnostics

Coverage reports, orphaned-reference detection, connection validation
and compact status.

- [`entropia_ocr_coverage()`](https://humalab.github.io/EntropIA-R/reference/entropia_ocr_coverage.md)
  : OCR coverage (lazy)
- [`entropia_metadata_coverage()`](https://humalab.github.io/EntropIA-R/reference/entropia_metadata_coverage.md)
  : Metadata coverage (lazy)
- [`entropia_corpus_quality()`](https://humalab.github.io/EntropIA-R/reference/entropia_corpus_quality.md)
  : Combined corpus quality report
- [`entropia_orphans()`](https://humalab.github.io/EntropIA-R/reference/entropia_orphans.md)
  : Detect orphaned rows (broken conceptual foreign keys)
- [`entropia_validate()`](https://humalab.github.io/EntropIA-R/reference/entropia_validate.md)
  : Validate the structure of an EntropIA database
- [`entropia_status()`](https://humalab.github.io/EntropIA-R/reference/entropia_status.md)
  : Compact status summary of an EntropIA database

## Research layer

Entity relations, LLM result reconstruction, conversations with
citations, and the sync-metadata surface.

- [`entropia_entity_relations()`](https://humalab.github.io/EntropIA-R/reference/entropia_entity_relations.md)
  : Entity relations (triples with item and collection context)
- [`entropia_reconstruct_analysis()`](https://humalab.github.io/EntropIA-R/reference/entropia_reconstruct_analysis.md)
  : Reconstruct LLM analyses against their targets
- [`entropia_conversation()`](https://humalab.github.io/EntropIA-R/reference/entropia_conversation.md)
  : One RAG conversation with its ordered messages
- [`entropia_sync_info()`](https://humalab.github.io/EntropIA-R/reference/entropia_sync_info.md)
  : Whitelisted sync settings as a typed tibble
- [`entropia_sync_versions()`](https://humalab.github.io/EntropIA-R/reference/entropia_sync_versions.md)
  : Sync row versions (lazy)
- [`entropia_conflicts()`](https://humalab.github.io/EntropIA-R/reference/entropia_conflicts.md)
  : Sync conflicts (lazy)

## Analysis

Operate on collected tibbles: temporal profiles, document lengths,
entity/topic frequency, collection comparison, and reproducible datasets
with provenance.

- [`entropia_temporal_profile()`](https://humalab.github.io/EntropIA-R/reference/entropia_temporal_profile.md)
  **\[experimental\]** : Temporal profile (counts by time bucket)
- [`entropia_document_lengths()`](https://humalab.github.io/EntropIA-R/reference/entropia_document_lengths.md)
  **\[experimental\]** : Document lengths (chars/words per row)
- [`entropia_entity_frequency()`](https://humalab.github.io/EntropIA-R/reference/entropia_entity_frequency.md)
  **\[experimental\]** : Entity frequency (top entities by type)
- [`entropia_topic_frequency()`](https://humalab.github.io/EntropIA-R/reference/entropia_topic_frequency.md)
  **\[experimental\]** : Topic frequency (items per topic)
- [`entropia_compare_collections()`](https://humalab.github.io/EntropIA-R/reference/entropia_compare_collections.md)
  **\[experimental\]** : Compare collections (per-collection summary)
- [`entropia_analysis_dataset()`](https://humalab.github.io/EntropIA-R/reference/entropia_analysis_dataset.md)
  **\[experimental\]** : Build a reproducible analysis dataset

## Visualization

ggplot2 helpers on analysis summaries (Suggests).

- [`entropia_plot_temporal()`](https://humalab.github.io/EntropIA-R/reference/entropia_plot_temporal.md)
  : Plot a temporal profile
- [`entropia_plot_entities()`](https://humalab.github.io/EntropIA-R/reference/entropia_plot_entities.md)
  : Plot entity frequencies
- [`entropia_plot_coverage()`](https://humalab.github.io/EntropIA-R/reference/entropia_plot_coverage.md)
  : Plot corpus coverage

## Export & provenance

Export tibbles or lazy queries to disk (streamed for delimited formats)
and read/write provenance sidecars.

- [`entropia_export()`](https://humalab.github.io/EntropIA-R/reference/entropia_export.md)
  : Export data to a file
- [`entropia_provenance()`](https://humalab.github.io/EntropIA-R/reference/entropia_provenance.md)
  : Read the provenance stamp of a reproducible dataset
- [`entropia_write_provenance()`](https://humalab.github.io/EntropIA-R/reference/entropia_write_provenance.md)
  : Write a provenance sidecar (JSON)

## Write API (v2 stubs)

v1 stubs for the v2 write API. All error with
`entropia_error_write_disabled` and documented guidance.

- [`entropia_insert()`](https://humalab.github.io/EntropIA-R/reference/entropia_insert.md)
  : Insert rows (v2 contract; errors in v1)
- [`entropia_update()`](https://humalab.github.io/EntropIA-R/reference/entropia_update.md)
  : Update rows (v2 contract; errors in v1)
- [`entropia_upsert()`](https://humalab.github.io/EntropIA-R/reference/entropia_upsert.md)
  : Upsert rows (v2 contract; errors in v1)
- [`entropia_delete()`](https://humalab.github.io/EntropIA-R/reference/entropia_delete.md)
  : Delete rows (v2 contract; errors in v1)

## Package

Package-level documentation.

- [`entropiaR`](https://humalab.github.io/EntropIA-R/reference/entropiaR-package.md)
  [`entropiaR-package`](https://humalab.github.io/EntropIA-R/reference/entropiaR-package.md)
  : entropiaR: Tidy Interface to EntropIA SQLite Databases
