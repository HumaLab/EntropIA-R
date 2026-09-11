# Versioned SQL fragments.
#
# ent_sql(version, id) returns the SQL fragment for `id` that applies to a
# database at schema `version`. Fragments are embedded as R data rather than
# shipped as .sql files under R/sql/: non-R files in R/ are not copied into
# installed packages (only the lazyload database is), so file-based fragments
# would break after installation. The structure mirrors the plan's design
# (R/sql/ fragments selected by the schema version string).
#
# Each fragment id maps to a list with:
#   default           -- the reference (post-0029) SQL, with ?name placeholders
#   "pre-<migration>" -- a variant used while version < migration, i.e. before
#                        the migration that introduced the column/behavior the
#                        default relies on (e.g. llm_results.target_type).
# Fragment SQL uses DBI::sqlInterpolate()-style ?name placeholders; callers
# interpolate with DBI::sqlInterpolate() before execution.

ent_sql_fragments <- function() {
  list(
    # llm_results filtered by job target_type. Requires 0019+ (the target_type
    # column was added in 0019_llm_results_target_type). Pre-0019 databases
    # have no such column, so the filter is unavailable and the full table is
    # returned (documented fallback).
    llm_results_target = list(
      default = paste0(
        "SELECT * FROM llm_results\n",
        "WHERE target_type = ?target"
      ),
      "pre-0019_llm_results_target_type" = paste0(
        "SELECT * FROM llm_results\n",
        "-- pre-0019: no target_type column; the target filter is unavailable"
      )
    )
  )
}

# Escape a user query for safe FTS5 MATCH: split on whitespace, wrap each
# token in double-quotes (escaping any embedded double-quote by doubling it),
# and join with spaces. This preserves the implicit-AND token semantics while
# preventing FTS5 syntax errors from characters that the FTS5 query expression
# parser cannot handle (notably apostrophes in "O'Brien", "l'assembl<U+00E9>e").
ent_escape_fts5 <- function(query) {
  tokens <- strsplit(trimws(query), "\\s+")[[1L]]
  tokens <- tokens[nzchar(tokens)]
  escaped <- vapply(tokens, function(t) {
    t <- gsub('"', '""', t, fixed = TRUE)
    paste0('"', t, '"')
  }, character(1L), USE.NAMES = FALSE)
  paste(escaped, collapse = " ")
}

# Build the parameter-safe FTS5 search query for `index`. The user query is
# first escaped against FTS5 special characters by wrapping each whitespace
# token in double-quotes (see ent_escape_fts5()), then the resulting FTS5-safe
# string is escaped with DBI::dbQuoteString() into a SQL string literal before
# splicing into MATCH, so it can never break out of the literal
# (injection-safe). The `items` index joins fts_items.rowid -> items.rowid
# (the contentless FTS5 contract); the `chunks` index joins
# rag_chunks_fts.chunk_id -> rag_chunks.id. Both order by bm25() rank
# ascending (best first). `limit` is a validated positive integer, never user
# text, so it is interpolated directly.
ent_search_sql <- function(con, query, index = c("items", "chunks"), limit = NULL) {
  index <- match.arg(index)
  q <- DBI::dbQuoteString(con, ent_escape_fts5(query))
  if (index == "items") {
    sql <- paste0(
      "SELECT i.*, bm25(fts_items) AS rank\n",
      "FROM fts_items\n",
      "JOIN items i ON i.rowid = fts_items.rowid\n",
      "WHERE fts_items MATCH ", q, "\n",
      "ORDER BY rank"
    )
  } else {
    sql <- paste0(
      "SELECT c.*, bm25(rag_chunks_fts) AS rank\n",
      "FROM rag_chunks_fts\n",
      "JOIN rag_chunks c ON c.id = rag_chunks_fts.chunk_id\n",
      "WHERE rag_chunks_fts MATCH ", q, "\n",
      "ORDER BY rank"
    )
  }
  if (!is.null(limit)) {
    sql <- paste0(sql, "\nLIMIT ", as.integer(limit))
  }
  dbplyr::sql(sql)
}

# Build the SQL that strips all OCR page markers (![](page=n,bbox=[...])) from
# a `text` column, carried alongside the other `cols` per row. Implemented as a
# recursive CTE because SQLite ships no regexp function and the marker payload
# is variable: each row starts at n = 0 and recurses one marker at a time until
# none remain. The marker contains no ')', so the first ')' at or after the
# marker start closes it. A ranked CTE then keeps the final iteration (highest
# n) of each `id` chain, so the result has exactly one row per input row.
# `sub_sql` is the rendered inner query (its output columns must be `cols`).
ent_strip_markers_sql <- function(cols, sub_sql) {
  # The recursive CTE emits the substr(text, ...) expression in the position
  # where "text" appears in the column list, so text MUST be last for the
  # column signatures to align across the anchor and recursive members.
  # entropia_text() guarantees this; assert it here so a future caller that
  # violates the assumption fails fast rather than silently misaligning columns.
  stopifnot(
    "text" %in% cols,
    identical(cols[length(cols)], "text"),
    length(cols) >= 2L
  )
  strip_cols <- paste0('"', cols, '"', collapse = ", ")
  inner_cols <- paste0('"', setdiff(cols, "text"), '"', collapse = ", ")
  paste0(
    "WITH RECURSIVE ent_text(", strip_cols, ", n) AS (\n",
    "  SELECT ", strip_cols, ", 0\n",
    "  FROM (", sub_sql, ")\n",
    "  UNION ALL\n",
    "  SELECT ", inner_cols, ",\n",
    "    substr(text, 1, instr(text, '![](') - 1) ||\n",
    "    substr(text, instr(text, '![](') + instr(substr(text, instr(text,\n",
    "      '![](') + 1), ')') + 1),\n",
    "    n + 1\n",
    "  FROM ent_text\n",
    "  WHERE instr(text, '![](') > 0\n",
    "    AND instr(substr(text, instr(text, '![](')), ')') > 0\n",
    "),\n",
    "ent_text_ranked AS (\n",
    "  SELECT ", strip_cols, ",\n",
    "    ROW_NUMBER() OVER (PARTITION BY \"id\" ORDER BY n DESC) AS ent_rn\n",
    "  FROM ent_text\n",
    ")\n",
    "SELECT ", strip_cols, "\n",
    "FROM ent_text_ranked\n",
    "WHERE ent_rn = 1"
  )
}

# Resolve a versioned SQL fragment. When the database version predates one or
# more `pre-<migration>` variants, the variant with the highest migration
# (closest to the database) wins; an NA/unknown version falls back to the
# default fragment. Aborts with entropia_error_sql_fragment_missing for an
# unknown id.
ent_sql <- function(version, id) {
  frags <- ent_sql_fragments()[[id]]
  if (is.null(frags)) {
    ent_abort(
      "entropia_error_sql_fragment_missing",
      "Unknown SQL fragment {.val {id}}.",
      id = id
    )
  }
  if (!is.null(version) && !is.na(version)) {
    pre <- names(frags)[startsWith(names(frags), "pre-")]
    if (length(pre) > 0L) {
      applicable <- pre[vapply(
        sub("^pre-", "", pre),
        function(mig) version < mig,
        logical(1)
      )]
      if (length(applicable) > 0L) {
        # max() is lexicographic; the highest pre-<migration> not yet reached is
        # the variant closest to the database's version.
        return(frags[[max(applicable)]])
      }
    }
  }
  frags$default
}
