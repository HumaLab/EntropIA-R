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
