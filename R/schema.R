# Schema introspection and the column contract.
#
# The schema surface has two sources of truth:
#   1. the live database (sqlite_master + PRAGMA table_xinfo) -- what exists;
#   2. inst/schemas/manifest.json -- the shipped column contract for the
#      post-0029 reference schema, tagged with the migration that guarantees
#      each column.
# entropia_schema_info() merges the two so callers see both what the package
# understands and what the database actually has. The compatibility policy
# (Task 6) consumes the same primitives.

# Tables readable by the package: every table in sqlite_master except SQLite
# internals (sqlite_*) and FTS5 shadow tables (the fts_*_config/data/docsize/
# idx/content companions).
ent_tables <- function(con) {
  tabs <- DBI::dbGetQuery(
    con,
    "SELECT name, sql FROM sqlite_master WHERE type = 'table'"
  )
  virtual <- tabs$name[!is.na(tabs$sql) & grepl("^CREATE VIRTUAL TABLE", tabs$sql)]
  shadow <- unlist(lapply(virtual, function(v) {
    paste0(v, c("_config", "_data", "_docsize", "_idx", "_content"))
  }), use.names = FALSE)
  keep <- !(startsWith(tabs$name, "sqlite_") | tabs$name %in% shadow)
  sort(tabs$name[keep])
}

# Columns of a table via PRAGMA table_xinfo: regular columns (hidden == 0)
# plus VIRTUAL and STORED generated columns (hidden != 1). Errors with
# entropia_error_table_missing when the table does not exist.
ent_columns <- function(con, table) {
  available <- ent_tables(con)
  if (!table %in% available) {
    ent_abort(
      "entropia_error_table_missing",
      c(
        "Table {.val {table}} does not exist in this database.",
        i = "Available tables: {.val {available}}."
      ),
      table = table
    )
  }
  q <- DBI::dbQuoteIdentifier(con, table)
  info <- DBI::dbGetQuery(con, paste0("PRAGMA table_xinfo(", q, ")"))
  info <- info[info$hidden != 1L, , drop = FALSE]
  data.frame(
    name = info$name,
    type = info$type,
    notnull = as.logical(info$notnull),
    pk = as.integer(info$pk),
    hidden = as.integer(info$hidden),
    stringsAsFactors = FALSE
  )
}

# Verify that every column in `columns` exists on `table`; abort with
# entropia_error_column_missing listing the columns that are actually present.
# A missing table surfaces as entropia_error_table_missing (from ent_columns),
# which is the more fundamental failure. Accessors (Task 9+) call this before
# querying a table so failures stay stable and actionable.
ent_require_columns <- function(con, table, columns) {
  cols <- tryCatch(ent_columns(con, table)$name, error = function(e) e)
  # A missing table surfaces as entropia_error_table_missing (from ent_columns);
  # re-raise it rather than reporting every requested column as missing, which
  # would hide the more fundamental failure.
  if (inherits(cols, "condition")) {
    rlang::abort(
      "Table lookup failed.",
      parent = cols,
      class = setdiff(class(cols), c("error", "condition", "rlang_error"))
    )
  }
  missing <- setdiff(columns, cols)
  if (length(missing) > 0L) {
    ent_abort(
      "entropia_error_column_missing",
      c(
        "Column(s) not found on table {.val {table}}: {.val {missing}}.",
        i = "Available columns: {.val {cols}}."
      ),
      table = table, columns = missing
    )
  }
  invisible(TRUE)
}

# Do all `cols` exist on `table`? Used to gate optional-column behaviour (e.g.
# the entities soft-delete marker `source` on schemas that predate migration
# 0009) without raising on absent tables or columns.
ent_has_columns <- function(con, table, cols) {
  live <- tryCatch(ent_columns(con, table)$name, error = function(e) character(0))
  all(cols %in% live)
}

# Path to the bundled schema manifest inside the installed package.
ent_manifest_path <- function() {
  system.file("schemas", "manifest.json", package = "entropiaR")
}

# Load the column contract. Returns a nested list (fromJSON with
# simplifyVector = FALSE so names and order are preserved exactly).
# Deliberately uncached: alternate manifests (including mocked paths) must
# reflect file replacement even when filesystem timestamps have coarse precision.
ent_manifest <- function() {
  p <- ent_manifest_path()
  if (!nzchar(p)) {
    ent_abort(
      "entropia_error_manifest_missing",
      c(
        "The schema manifest could not be found.",
        i = "Expected it at {.path inst/schemas/manifest.json} in the installed package."
      )
    )
  }
  jsonlite::fromJSON(p, simplifyVector = FALSE)
}

# Does a column with `min_version` (NULL = no migration guarantees it) apply to
# a database at schema version `ver`? Lexicographic comparison is safe because
# migration names are zero-padded fixed-width (e.g. "0029_rag_chunks").
ent_min_version_applies <- function(min_version, ver) {
  if (is.null(min_version) || is.na(min_version)) {
    return(TRUE) # repair/sync tables are expected at any version
  }
  if (is.null(ver) || is.na(ver)) {
    return(NA) # unknown database version -> unknown expectation
  }
  ver >= min_version
}

# Manifest columns absent from the live schema, one row per gap. `expected`
# records whether the database version should already have the column (TRUE),
# should not yet (FALSE), or whether that cannot be determined (NA). This is
# the raw material for the compatibility policy in Task 6.
ent_schema_gaps <- function(con) {
  ent_require_conn(con)
  mf <- ent_manifest()
  ver <- ent_current_version(con)
  live_tables <- ent_tables(con)
  out <- list()
  for (t in names(mf$tables)) {
    if (!t %in% live_tables) next # table absent entirely: handled elsewhere
    mentry <- mf$tables[[t]]
    live_cols <- ent_columns(con, t)$name
    for (c in names(mentry$columns)) {
      if (c %in% live_cols) next
      mc <- mentry$columns[[c]]
      mv <- mc$min_version %||% mentry$min_version %||% NULL
      out[[length(out) + 1]] <- data.frame(
        table = t,
        column = c,
        type = mc$type %||% NA_character_,
        required = isTRUE(mc$required),
        min_version = mv %||% NA_character_,
        current_version = ver %||% NA_character_,
        expected = ent_min_version_applies(mv, ver),
        stringsAsFactors = FALSE
      )
    }
  }
  if (length(out) == 0) {
    return(tibble::tibble(
      table = character(), column = character(), type = character(),
      required = logical(), min_version = character(),
      current_version = character(), expected = logical()
    ))
  }
  tibble::as_tibble(do.call(rbind, out))
}

#' Schema version of an EntropIA database
#'
#' Returns the authoritative schema version: the lexicographic maximum of the
#' `_migrations` table (e.g. `"0029_rag_chunks"`). `NA_character_` when the
#' database has no `_migrations` table.
#'
#' @param con A connection returned by [entropia_connect()].
#' @return A single string, or `NA_character_`.
#' @examples
#' con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
#'   package = "entropiaR"
#' ))
#' entropia_schema_version(con)
#' entropia_disconnect(con)
#' @export
entropia_schema_version <- function(con) {
  ent_require_conn(con)
  ent_current_version(con)
}

#' Tables, columns and typed contract of an EntropIA database
#'
#' Merges the live schema (from `PRAGMA table_xinfo`) with the shipped column
#' contract (`inst/schemas/manifest.json`). Every readable table gets one row
#' per column. `source` records whether the row came from the manifest contract
#' (`"manifest"`) or only exists in the live database (`"schema"`); columns
#' present in both are reported under the manifest (the contract is the typed
#' surface). `min_version` is the migration that guarantees the column, and
#' `required` marks columns whose absence is a compatibility failure once the
#' database reaches that version.
#'
#' @param con A connection returned by [entropia_connect()].
#' @return A tibble with columns `table`, `column`, `type`, `required`,
#'   `contract`, `min_version`, `source`, `presence` (logical) and `live_type`.
#'   Absent manifest tables and columns have `presence = FALSE` and missing
#'   `live_type`; `type` retains the manifest declaration where available.
#' @examples
#' con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
#'   package = "entropiaR"
#' ))
#' entropia_schema_info(con)
#' entropia_disconnect(con)
#' @export
entropia_schema_info <- function(con) {
  ent_require_conn(con)
  mf <- ent_manifest()
  rows <- list()
  live_tables <- ent_tables(con)
  for (t in sort(union(live_tables, names(mf$tables)))) {
    live <- if (t %in% live_tables) ent_columns(con, t) else
      data.frame(name = character(), type = character())
    mentry <- mf$tables[[t]]
    manifest_cols <- if (is.null(mentry)) character() else names(mentry$columns)
    live_only <- setdiff(live$name, manifest_cols)
    for (c in live_only) {
      i <- match(c, live$name)
      rows[[length(rows) + 1]] <- data.frame(
        table = t, column = c, type = live$type[i],
        required = FALSE, contract = NA_character_,
        min_version = NA_character_, source = "schema",
        presence = TRUE, live_type = live$type[i],
        stringsAsFactors = FALSE
      )
    }
    if (!is.null(mentry)) {
      for (c in manifest_cols) {
        mc <- mentry$columns[[c]]
        # Column-level min_version overrides the table-level one.
        mv <- mc$min_version %||% mentry$min_version %||% NA_character_
        rows[[length(rows) + 1]] <- data.frame(
          table = t, column = c, type = mc$type %||% NA_character_,
          required = isTRUE(mc$required),
          contract = mc$contract %||% NA_character_,
          min_version = mv, source = "manifest",
          presence = c %in% live$name,
          live_type = live$type[match(c, live$name)],
          stringsAsFactors = FALSE
        )
      }
    }
  }
  out <- if (length(rows) > 0) {
    do.call(rbind, rows)
  } else {
    data.frame(
      table = character(), column = character(), type = character(),
      required = logical(), contract = character(),
      min_version = character(), source = character(),
      presence = logical(), live_type = character(),
      stringsAsFactors = FALSE
    )
  }
  tibble::as_tibble(out)
}

# Compatibility layer + schema policies ---------------------------------------
#
# entropia_schema_compat() classifies a database against the shipped manifest;
# ent_compat_check() applies options(entropiaR.schema_policy) on connect. The
# manifest is the reference, the live schema is the ground truth, and the
# policy decides how loudly the difference is reported.

# Classify a version against the manifest head. Migration names are zero-padded
# fixed-width ("0029_rag_chunks"), so lexicographic comparison is correct.
ent_compat_status <- function(ver, head) {
  if (is.null(ver) || is.na(ver)) {
    return("unknown")
  }
  if (ver == head) {
    return("known")
  }
  if (ver > head) {
    return("newer")
  }
  "older"
}

#' Schema compatibility status of an EntropIA database
#'
#' Classifies a database against the shipped column contract
#' (`inst/schemas/manifest.json`). The status is one of:
#'
#' - `"known"`: the schema version matches the manifest head (`0029_rag_chunks`).
#' - `"newer"`: the database version is lexicographically ahead of the manifest
#'   head -- a future EntropIA wrote it.
#' - `"older"`: the database version predates the manifest head.
#' - `"unknown"`: no `_migrations` table (or an empty one); version undetectable.
#'
#' The required-column check uses the manifest contract: columns tagged
#' `required = TRUE` whose `min_version` is already reached by the database
#' version must exist in the live schema. Missing ones are listed in
#' `required_missing` and make the database incompatible. Unknown versions
#' conservatively require manifest-required columns on existing tables.
#' The core tables `collections`, `items` and `assets` must always exist;
#' missing non-core tables are permitted for minimal databases.
#'
#' @param con A connection returned by [entropia_connect()].
#' @return A list of class `entropia_schema_compat` with elements `status`,
#'   `version`, `manifest_head`, `gaps` (the full expected-but-absent column
#'   table for existing tables), `required_missing`, `optional_missing`,
#'   `required_tables_missing` and `compatible`.
#' @examples
#' con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
#'   package = "entropiaR"
#' ))
#' entropia_schema_compat(con)
#' entropia_disconnect(con)
#' @export
entropia_schema_compat <- function(con) {
  ent_require_conn(con)
  mf <- ent_manifest()
  ver <- ent_current_version(con)
  head <- mf$schema_head

  status <- ent_compat_status(ver, head)
  gaps <- ent_schema_gaps(con)
  expected <- gaps[is.na(gaps$expected) | gaps$expected, , drop = FALSE]
  required_tables_missing <- setdiff(ent_core_tables, ent_tables(con))
  required_missing <- expected[expected$required, , drop = FALSE]
  optional_missing <- expected[!expected$required, , drop = FALSE]

  out <- list(
    status = status,
    version = ver,
    manifest_head = head,
    gaps = gaps,
    required_missing = required_missing,
    optional_missing = optional_missing,
    required_tables_missing = required_tables_missing,
    compatible = nrow(required_missing) == 0L && length(required_tables_missing) == 0L
  )
  class(out) <- "entropia_schema_compat"
  out
}

# Abort for a genuinely incompatible database (missing required columns, or a
# hard policy stop). Message is cli-formatted and actionable. Interpolated
# values (version, missing, manifest_head) are provided through an explicit
# message environment: cli evaluates `{}` expressions against .envir, not the
# call's named arguments, so the values must be in scope there.
ent_abort_schema_incompatible <- function(compat) {
  if (nrow(compat$required_missing) == 0L &&
      length(compat$required_tables_missing) > 0L) {
    missing <- compat$required_tables_missing
    ent_abort(
      "entropia_error_schema_incompatible",
      c(
        "Database is missing required core table(s): {.val {missing}}.",
        i = "The collections, items and assets tables are required at every schema version.",
        i = "To proceed anyway, set {.code options(entropiaR.schema_policy = 'allow')}."
      )
    )
  }
  if (nrow(compat$required_missing) > 0L) {
    msg_env <- rlang::env(
      version = compat$version,
      missing = paste0(
        compat$required_missing$table, ".",
        compat$required_missing$column,
        collapse = ", "
      )
    )
    ent_abort(
      "entropia_error_schema_incompatible",
      c(
        paste0(
          "Database at schema version {.val {version}} is missing required ",
          "column(s): {missing}."
        ),
        i = "The database does not satisfy the {.pkg entropiaR} column contract.",
        i = paste0(
          "If it is a valid EntropIA database, update {.pkg entropiaR}; ",
          "otherwise the file may be partial or corrupt. To proceed anyway, ",
          "set {.code options(entropiaR.schema_policy = 'allow')}."
        )
      ),
      .envir = msg_env
    )
  }
  msg_env <- rlang::env(
    version = compat$version,
    manifest_head = compat$manifest_head
  )
  ent_abort(
    "entropia_error_schema_incompatible",
    c(
      "Schema policy is {.val error} and this database is not at the reference schema.",
      paste0(
        "Database schema version: {.val {version}} ",
        "(reference {.val {manifest_head}})."
      ),
      i = paste0(
        "Set {.code options(entropiaR.schema_policy = 'warn')} to proceed ",
        "read-only with a warning, or {.code 'allow'} to proceed silently."
      )
    ),
    .envir = msg_env
  )
}

# Warning for a tolerable schema deviation (older/newer/unknown version, or a
# known version with optional columns missing). Silent under `allow`; the
# message is cli-formatted and actionable.
ent_warn_schema_compat <- function(compat) {
  msg_env <- rlang::env(
    version = compat$version,
    manifest_head = compat$manifest_head
  )
  bullets <- switch(compat$status,
    newer = c(
      paste0(
        "Database schema version {.val {version}} is newer than the latest ",
        "{.pkg entropiaR} understands ({.val {manifest_head}})."
      ),
      i = "Read-only access continues, but new columns may not be typed."
    ),
    older = c(
      paste0(
        "Database schema version {.val {version}} is older than the ",
        "reference {.val {manifest_head}}."
      ),
      i = "Required columns are present; proceeding read-only."
    ),
    unknown = c(
      "Database schema version is unknown (no {.code _migrations} table).",
      i = "Proceeding read-only."
    ),
    c("Database schema version {.val {version}} matches the reference schema.")
  )
  if (nrow(compat$optional_missing) > 0L) {
    msg_env$missing <- paste0(
      compat$optional_missing$table, ".",
      compat$optional_missing$column,
      collapse = ", "
    )
    bullets <- c(bullets, i = "Optional columns absent: {missing}.")
  }
  bullets <- c(
    bullets,
    i = "Set {.code options(entropiaR.schema_policy = 'allow')} to silence this."
  )
  cli::cli_warn(bullets, class = "entropia_warn_schema", .envir = msg_env)
}

# Apply policy even without migrations: core tables remain mandatory.
# `allow` is silent; `warn` rejects structural failures but warns on tolerable
# deviations; `error` rejects every deviation. quiet never suppresses errors.
ent_compat_check <- function(con, policy, quiet = FALSE) {
  compat <- entropia_schema_compat(con)
  if (identical(policy, "allow")) {
    return(invisible(compat))
  }
  if (!compat$compatible) {
    ent_abort_schema_incompatible(compat)
  }
  if (identical(policy, "error") &&
    !(identical(compat$status, "known") && nrow(compat$optional_missing) == 0L)) {
    ent_abort_schema_incompatible(compat)
  }
  if (identical(compat$status, "known") && nrow(compat$optional_missing) == 0L) {
    return(invisible(compat))
  }
  if (!quiet) {
    ent_warn_schema_compat(compat)
  }
  invisible(compat)
}
