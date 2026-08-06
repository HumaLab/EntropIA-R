# Diagnostics: entropia_validate() and entropia_status().
#
# validate() reports structural health as a findings tibble; status() renders
# a compact read-only summary. Both are pure reads -- no writes, no EXPLAIN,
# no data movement. They share the row-count and sync_meta primitives defined
# here; ent_sync_meta() is also the base for the Task 8 sync surface.

# Tables whose absence is a hard structural failure (the domain backbone).
# Every other manifest table may legitimately be absent from a minimal or
# partial database (sync never enabled, an old build without RAG), so a
# missing non-core table is a warning, not an error.
ent_core_tables <- c("collections", "items", "assets")

# Read sync_meta as a named character vector (key -> value). sync_meta is a
# key/value table (EAV); it has no fixed columns, so everything is read as
# text and the caller coerces the fields it understands.
ent_sync_meta <- function(con) {
  if (!DBI::dbExistsTable(con, "sync_meta")) {
    return(stats::setNames(character(), character()))
  }
  sm <- DBI::dbGetQuery(con, "SELECT key, value FROM sync_meta")
  out <- as.character(sm$value)
  names(out) <- as.character(sm$key)
  out
}

# Row counts for every readable table, sorted descending. Tables that cannot
# be counted (e.g. a partial read on a corrupt database) are dropped silently.
ent_row_counts <- function(con) {
  tabs <- ent_tables(con)
  out <- stats::setNames(integer(), character())
  for (t in tabs) {
    n <- tryCatch(
      as.integer(DBI::dbGetQuery(con, paste0("SELECT count(*) AS n FROM ", t))$n),
      error = function(e) NA_integer_
    )
    if (!is.na(n)) {
      out[[t]] <- n
    }
  }
  out[order(out, decreasing = TRUE)]
}

# Build the findings tibble from a list of one-row data.frames, sorted by
# severity (error first) then kind/table/column so the most important findings
# come first.
ent_findings_tibble <- function(findings) {
  if (length(findings) == 0L) {
    out <- data.frame(
      severity = character(), kind = character(), table = character(),
      column = character(), message = character(), stringsAsFactors = FALSE
    )
  } else {
    out <- do.call(rbind, findings)
  }
  sev <- factor(out$severity, levels = c("error", "warning", "info"))
  out <- out[order(sev, out$kind, out$table, out$column), , drop = FALSE]
  rownames(out) <- NULL
  tibble::as_tibble(out)
}

#' Validate the structure of an EntropIA database
#'
#' Reports structural health as a tibble of findings. The check is read-only
#' and `EXPLAIN`-free: it compares the live schema (`sqlite_master` +
#' `PRAGMA table_xinfo`) against the shipped column contract and counts rows.
#'
#' Each finding has a `severity` (`"error"`, `"warning"`, `"info"`), a `kind`
#' (`"table_missing"`, `"column_missing"`, `"empty_database"`,
#' `"no_migrations"`, or `"unreadable"`), the affected `table`/`column` (or
#' `NA`), and a plain-text `message`. A healthy database returns an empty
#' findings tibble: zero error-severity findings and no warnings for a
#' complete post-0029 schema. Row counts for every readable table and the
#' detected schema version are attached as the `row_counts` and
#' `schema_version` attributes.
#'
#' Unlike the accessors, `validate()` never raises `entropia_error_table_missing`
#' or `entropia_error_column_missing`: structural gaps are findings, not errors.
#' The one exception is an unreadable (corrupt) file, which yields a single
#' `"unreadable"` finding of severity `"error"`.
#'
#' @param con A connection returned by [entropia_connect()].
#' @return A tibble of findings with columns `severity`, `kind`, `table`,
#'   `column` and `message`, plus `row_counts` and `schema_version` attributes.
#' @export
entropia_validate <- function(con) {
  ent_require_conn(con)

  # Unreadable database (e.g. corrupt file): the first structural query fails.
  # Report one error finding and stop; there is nothing further to diagnose.
  live_tables <- tryCatch(ent_tables(con), error = function(e) NULL)
  if (is.null(live_tables)) {
    msg <- tryCatch(
      conditionMessage(DBI::dbGetQuery(con, "SELECT 1")),
      error = function(e) conditionMessage(e)
    )
    out <- ent_findings_tibble(list(data.frame(
      severity = "error", kind = "unreadable",
      table = NA_character_, column = NA_character_,
      message = paste0("The database cannot be read: ", msg),
      stringsAsFactors = FALSE
    )))
    attr(out, "schema_version") <- NA_character_
    return(out)
  }

  mf <- ent_manifest()
  ver <- ent_current_version(con)
  findings <- list()

  for (t in names(mf$tables)) {
    mentry <- mf$tables[[t]]
    is_core <- t %in% ent_core_tables
    if (!t %in% live_tables) {
      # Only flag a missing table once the migration that guarantees it is
      # reached (or the version is unknown); a database that predates the
      # table is not broken.
      expected <- ent_min_version_applies(mentry$min_version %||% NULL, ver)
      if (isTRUE(expected) || is.na(expected)) {
        findings[[length(findings) + 1L]] <- data.frame(
          severity = if (is_core) "error" else "warning",
          kind = "table_missing",
          table = t, column = NA_character_,
          message = if (is_core) {
            paste0("Core table is missing: ", t, ".")
          } else {
            paste0("Optional table is missing: ", t, ".")
          },
          stringsAsFactors = FALSE
        )
      }
      next
    }
    # Table present: check every manifest column the version should already
    # have. A required column missing at its min_version is an error; an
    # optional one is a warning.
    live_cols <- ent_columns(con, t)$name
    for (c in names(mentry$columns)) {
      if (c %in% live_cols) next
      mc <- mentry$columns[[c]]
      expected <- ent_min_version_applies(mc$min_version %||% NULL, ver)
      if (isFALSE(expected)) next
      req <- isTRUE(mc$required)
      findings[[length(findings) + 1L]] <- data.frame(
        severity = if (req) "error" else "warning",
        kind = "column_missing",
        table = t, column = c,
        message = if (req) {
          paste0("Required column is missing: ", t, ".", c, ".")
        } else {
          paste0("Optional column is missing: ", t, ".", c, ".")
        },
        stringsAsFactors = FALSE
      )
    }
  }

  # Schema version contract: no _migrations table (or an empty one) means the
  # version is unknown. Informative, not a failure.
  if (is.na(ver)) {
    findings[[length(findings) + 1L]] <- data.frame(
      severity = "warning", kind = "no_migrations",
      table = NA_character_, column = NA_character_,
      message = paste0(
        "The database has no _migrations table; ",
        "schema version is unknown."
      ),
      stringsAsFactors = FALSE
    )
  }

  # Empty-database detection: the core backbone exists but holds no rows.
  row_counts <- ent_row_counts(con)
  core_counts <- row_counts[intersect(ent_core_tables, names(row_counts))]
  if (length(core_counts) == length(ent_core_tables) && sum(core_counts) == 0L) {
    findings[[length(findings) + 1L]] <- data.frame(
      severity = "warning", kind = "empty_database",
      table = NA_character_, column = NA_character_,
      message = paste0(
        "The database is empty: no rows in collections, items or assets."
      ),
      stringsAsFactors = FALSE
    )
  }

  out <- ent_findings_tibble(findings)
  attr(out, "row_counts") <- row_counts
  attr(out, "schema_version") <- ver
  out
}

# Sync freshness for entropia_status(): the whitelisted sync_meta fields,
# coerced to their natural types. last_sync_at is epoch milliseconds (per the
# column contract); capture_enabled and triggers_version are small integers.
ent_status_sync <- function(con) {
  sm <- ent_sync_meta(con)
  # Single-bracket indexing: a missing key yields NA ([[ would throw).
  last_raw <- sm["last_sync_at"]
  last_sync_at <- if (!is.na(last_raw) && nzchar(last_raw)) {
    as.POSIXct(as.numeric(last_raw) / 1000, origin = "1970-01-01", tz = "UTC")
  } else {
    NA_real_
  }
  cap_raw <- sm["capture_enabled"]
  capture_enabled <- if (!is.na(cap_raw) && nzchar(cap_raw)) {
    as.integer(cap_raw) == 1L
  } else {
    NA
  }
  trg_raw <- sm["triggers_version"]
  triggers_version <- if (!is.na(trg_raw) && nzchar(trg_raw)) {
    as.integer(trg_raw)
  } else {
    NA_integer_
  }
  list(
    last_sync_at = last_sync_at,
    capture_enabled = capture_enabled,
    triggers_version = triggers_version
  )
}

# WAL state for entropia_status(): journal mode from PRAGMA plus sidecar file
# presence next to the database path. A live EntropIA instance holds the WAL,
# so `wal_present = TRUE` with sidecar sizes is the signal to copy/snapshot.
ent_status_wal <- function(con, path) {
  journal <- tryCatch(
    DBI::dbGetQuery(con, "PRAGMA journal_mode")[[1]],
    error = function(e) NA_character_
  )
  wal_present <- shm_present <- FALSE
  wal_size <- NA_real_
  if (!is.na(path) && !identical(path, ":memory:")) {
    wal_present <- file.exists(paste0(path, "-wal"))
    shm_present <- file.exists(paste0(path, "-shm"))
    if (wal_present) {
      wal_size <- tryCatch(file.info(paste0(path, "-wal"))$size,
                           error = function(e) NA_real_)
    }
  }
  list(
    journal_mode = journal,
    wal_present = wal_present,
    shm_present = shm_present,
    wal_size = wal_size
  )
}

#' Compact status summary of an EntropIA database
#'
#' Read-only snapshot of a connection: path, mode, schema version, row counts
#' for every readable table (descending), sync freshness from `sync_meta`, and
#' WAL state (journal mode + sidecar files). Unlike [entropia_validate()],
#' `status()` never reports findings -- it describes the database.
#'
#' @param con A connection returned by [entropia_connect()].
#' @return A `entropia_status` list with elements `path`, `mode`,
#'   `schema_version`, `row_counts`, `sync`, `wal` and `valid`.
#' @export
entropia_status <- function(con) {
  ent_require_conn(con)
  path <- ent_attr(con, "path")
  if (is.na(path)) {
    path <- tryCatch(con@dbname, error = function(e) NA_character_)
    if (is.null(path)) path <- NA_character_
  }
  out <- list(
    path = path,
    mode = ent_attr(con, "mode", "read-only"),
    schema_version = ent_current_version(con),
    row_counts = ent_row_counts(con),
    sync = ent_status_sync(con),
    wal = ent_status_wal(con, path),
    valid = DBI::dbIsValid(con)
  )
  class(out) <- c("entropia_status", "list")
  out
}

#' @export
print.entropia_status <- function(x, ...) {
  ver <- x$schema_version
  if (is.na(ver)) ver <- "unknown"
  cat("entropiaR status\n")
  cat("  path:           ", x$path, "\n", sep = "")
  cat("  mode:           ", x$mode, "\n", sep = "")
  cat("  schema version: ", ver, "\n", sep = "")
  cat("  valid:          ", x$valid, "\n", sep = "")
  n <- length(x$row_counts)
  if (n == 0L) {
    top <- "(no readable tables)"
  } else {
    k <- min(5L, n)
    top <- paste0(
      names(x$row_counts)[seq_len(k)], "=", x$row_counts[seq_len(k)],
      collapse = ", "
    )
    if (n > 5L) top <- paste0(top, " (+", n - 5L, " more)")
  }
  cat("  row counts:     ", top, "\n", sep = "")
  last <- x$sync$last_sync_at
  last_txt <- if (is.null(last) || is.na(last)) "never" else format(last, tz = "UTC")
  cap <- x$sync$capture_enabled
  cap_txt <- if (is.null(cap) || is.na(cap)) "?" else cap
  cat("  sync:           last_sync_at ", last_txt,
      ", capture_enabled ", cap_txt, "\n", sep = "")
  cat("  journal:        ", x$wal$journal_mode, "\n", sep = "")
  cat("  wal sidecar:    ", x$wal$wal_present, sep = "")
  if (isTRUE(x$wal$wal_present) && !is.na(x$wal$wal_size)) {
    cat(" (", x$wal$wal_size, " bytes)", sep = "")
  }
  cat("\n")
  invisible(x)
}
