# entropia_connect and the entropia_conn methods.
#
# The connection is a read-only DBI connection to an EntropIA SQLite database.
# Read-only is enforced twice: the underlying RSQLite connection is opened with
# SQLITE_RO and PRAGMA query_only = ON is re-asserted on top (belt and braces).
# The returned object is an S4 subclass of SQLiteConnection, so every DBI and
# dbplyr function keeps working while the object carries the entropiaR contract
# (path, mode, schema_version, content_hash) as attributes.

# entropia_conn: S4 subclass of RSQLite's SQLiteConnection, defined at
# namespace load. Prepending a plain S3 class would break S4 generic dispatch
# (dbDisconnect/dbIsValid fail), so we subclass through the methods package
# instead -- DBI generics then resolve via the containment relationship.
if (!methods::isClass("entropia_conn")) {
  methods::setClass("entropia_conn", contains = "SQLiteConnection")
}

#' entropia_conn class
#'
#' A typed, read-only DBI connection to an EntropIA SQLite database. Subclass
#' of [RSQLite::SQLiteConnection-class]; carries `path`, `mode`,
#' `schema_version` and `content_hash` attributes.
#'
#' @name entropia_conn-class
#' @aliases entropia_conn
#' @keywords internal
NULL

#' Connect to an EntropIA SQLite database (read-only)
#'
#' Opens `path` as a read-only DBI connection. The returned object is an
#' `entropia_conn`: a typed subclass of [RSQLite::SQLiteConnection-class]
#' carrying the `path`, `mode`, `schema_version` and `content_hash`
#' attributes. All DBI and dbplyr functions keep working on it.
#'
#' @param path Path to the EntropIA SQLite database, or `":memory:"`.
#' @param write Must be `FALSE` in v1 (read-only). Passing `TRUE` errors with
#'   class `entropia_error_write_disabled` and v2 guidance.
#' @param validate Logical. When `TRUE` (default) the connection runs a
#'   lightweight sanity query (rejecting files that are not readable SQLite
#'   databases) and applies the schema compatibility policy controlled by
#'   `options(entropiaR.schema_policy)`.
#' @param quiet Logical. When `TRUE`, suppresses the schema-policy warning
#'   emitted on open (only affects the default `"warn"` policy; errors are
#'   never silenced).
#'
#' @return An `entropia_conn` object (S4, `SQLiteConnection` subclass).
#' @examples
#' con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
#'   package = "entropiaR"))
#' entropia_status(con)
#' entropia_disconnect(con)
#' @export
entropia_connect <- function(path, write = FALSE, validate = TRUE, quiet = FALSE) {
  if (!is.character(path) || length(path) != 1L || is.na(path)) {
    ent_abort(
      "entropia_error_invalid_argument",
      c(
        "{.arg path} must be a single path to an EntropIA SQLite database.",
        i = "Got {.type {typeof(path)}}."
      )
    )
  }
  if (isTRUE(write)) {
    ent_abort(
      "entropia_error_write_disabled",
      c(
        "Write access is not available in entropiaR v1.",
        i = paste0(
          "v1 is read-only. Write support ships in v2 -- ",
          "see {.file vignettes/administration.Rmd} for the design."
        )
      )
    )
  }

  is_memory <- identical(path, ":memory:")
  db_path <- path
  if (!is_memory) {
    db_path <- normalizePath(path, winslash = "/", mustWork = FALSE)
    if (!file.exists(db_path)) {
      ent_abort(
        "entropia_error_not_found",
        c(
          "Database file not found: {.path {path}}.",
          i = "Create the database with the EntropIA desktop app first, or pass a different path."
        ),
        path = path
      )
    }
    if (!ent_is_sqlite_header(db_path)) {
      ent_abort(
        "entropia_error_not_sqlite",
        c(
          "{.path {path}} is not a SQLite database.",
          i = paste0(
            "entropiaR reads EntropIA SQLite databases. ",
            "The file does not begin with the SQLite header."
          )
        ),
        path = path
      )
    }
  }

  con <- DBI::dbConnect(
    RSQLite::SQLite(),
    db_path,
    flags = RSQLite::SQLITE_RO,
    synchronous = NULL
  )
  DBI::dbExecute(con, "PRAGMA query_only = ON")

  if (validate) {
    err <- tryCatch(
      {
        DBI::dbGetQuery(con, "SELECT count(*) AS n FROM sqlite_master")
        ""
      },
      error = function(e) conditionMessage(e)
    )
    if (!identical(err, "")) {
      DBI::dbDisconnect(con)
      if (grepl("locked|busy", err)) {
        ent_abort(
          "entropia_error_locked",
          c(
            "The database at {.path {path}} is locked or busy.",
            i = paste0(
              "EntropIA may be running and holding the WAL write lock. ",
              "Retry when it is idle, or snapshot a copy with {.fn entropia_copy}."
            ),
            x = err
          ),
          path = path
        )
      }
      ent_abort(
        "entropia_error_not_sqlite",
        c(
          "{.path {path}} is not a readable SQLite database.",
          i = "The file exists but SQLite cannot read it. Is it a partial or corrupt export?",
          x = err
        ),
        path = path
      )
    }
  }

  # Schema compatibility policy (options(entropiaR.schema_policy)). Runs on
  # open so callers learn about older/newer schemas immediately; aborts close
  # the connection so nothing leaks.
  if (validate) {
    policy <- getOption("entropiaR.schema_policy", "warn")
    policy <- match.arg(policy, c("warn", "error", "allow"))
    compat_err <- tryCatch(
      {
        ent_compat_check(con, policy, quiet = quiet)
        NULL
      },
      error = function(e) e
    )
    if (!is.null(compat_err)) {
      DBI::dbDisconnect(con)
      rlang::cnd_signal(compat_err)
    }
  }

  con <- methods::as(con, "entropia_conn")
  attr(con, "path") <- if (is_memory) ":memory:" else db_path
  attr(con, "mode") <- "read-only"
  attr(con, "schema_version") <- ent_current_version(con)
  attr(con, "content_hash") <- ent_content_hash(con)
  con
}

#' Close an EntropIA connection
#'
#' Closes a connection opened by [entropia_connect()]. Idempotent: calling it
#' again on an already-closed connection is a no-op.
#'
#' @param con An `entropia_conn` (or any DBI connection).
#' @return `con`, invisibly.
#' @examples
#' con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
#'   package = "entropiaR"))
#' entropia_disconnect(con)
#' entropia_disconnect(con) # idempotent: safe on a closed connection
#' @export
entropia_disconnect <- function(con) {
  if (inherits(con, "DBIConnection") && DBI::dbIsValid(con)) {
    DBI::dbDisconnect(con)
  }
  invisible(con)
}

#' Snapshot a database to a new file (WAL-aware)
#'
#' Copies `con` to `dest` using SQLite's `VACUUM INTO`, which produces a single
#' consistent, self-contained database file. Because the snapshot is taken by
#' SQLite itself it reads through any live `-wal`/`-shm` sidecars, so it is safe
#' to run while EntropIA is holding the WAL. The destination must not already
#' exist.
#'
#' @param con An `entropia_conn` (or any DBI connection).
#' @param dest Destination file path. Must not exist.
#' @return The normalized `dest` path, invisibly.
#' @examples
#' con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
#'   package = "entropiaR"))
#' dest <- tempfile(fileext = ".sqlite")
#' entropia_copy(con, dest)
#' copy_con <- entropia_connect(dest)
#' entropia_status(copy_con)
#' entropia_disconnect(copy_con)
#' entropia_disconnect(con)
#' @export
entropia_copy <- function(con, dest) {
  if (!is.character(dest) || length(dest) != 1L || is.na(dest)) {
    ent_abort("entropia_error_invalid_argument", "{.arg dest} must be a single path.")
  }
  dest <- normalizePath(dest, winslash = "/", mustWork = FALSE)
  if (file.exists(dest)) {
    ent_abort(
      "entropia_error_dest_exists",
      c(
        "Destination already exists: {.path {dest}}.",
        i = "Refusing to overwrite. Pick a new path or remove the file first."
      )
    )
  }
  quoted <- DBI::dbQuoteString(con, dest)
  # PRAGMA query_only blocks VACUUM INTO (it writes a new file). Lift it just
  # for the snapshot and restore it on exit: the file is still open SQLITE_RO,
  # so the source database is never written.
  prior <- DBI::dbGetQuery(con, "PRAGMA query_only")[[1]]
  if (isTRUE(prior == 1)) DBI::dbExecute(con, "PRAGMA query_only = OFF")
  on.exit(
    if (isTRUE(prior == 1)) DBI::dbExecute(con, "PRAGMA query_only = ON"),
    add = TRUE
  )
  tryCatch(
    DBI::dbExecute(con, paste0("VACUUM INTO ", quoted)),
    error = function(e) {
      msg <- conditionMessage(e)
      if (grepl("locked|busy", msg)) {
        ent_abort(
          "entropia_error_locked",
          c(
            "The database at {.path {ent_attr(con, 'path')}} is locked or busy.",
            i = "Retry when EntropIA is idle."
          ),
          path = ent_attr(con, "path")
        )
      }
      ent_abort(
        "entropia_error_copy_failed",
        c("Could not copy the database to {.path {dest}}.", x = msg)
      )
    }
  )
  invisible(dest)
}

# S3 methods for the entropia_conn class -------------------------------------

#' @export
format.entropia_conn <- function(x, ...) {
  ver <- ent_attr(x, "schema_version")
  if (is.na(ver)) ver <- "unknown"
  hash <- ent_attr(x, "content_hash")
  hash_short <- if (is.na(hash)) "n/a" else substr(hash, 1, 12)
  paste0(
    "<entropiaR connection> ", ent_attr(x, "mode"), "\n",
    "  path:    ", ent_attr(x, "path"), "\n",
    "  schema:  ", ver, "\n",
    "  content: ", hash_short
  )
}

#' @export
print.entropia_conn <- function(x, ...) {
  cat(format(x, ...), "\n")
  invisible(x)
}

#' @export
summary.entropia_conn <- function(object, ...) {
  out <- list(
    path = ent_attr(object, "path"),
    mode = ent_attr(object, "mode"),
    schema_version = ent_attr(object, "schema_version"),
    content_hash = ent_attr(object, "content_hash"),
    valid = DBI::dbIsValid(object)
  )
  class(out) <- c("summary.entropia_conn", "list")
  out
}

#' @export
print.summary.entropia_conn <- function(x, ...) {
  ver <- x$schema_version
  if (is.na(ver)) ver <- "unknown"
  cat("entropiaR connection summary\n")
  cat("  path:           ", x$path, "\n", sep = "")
  cat("  mode:           ", x$mode, "\n", sep = "")
  cat("  schema version: ", ver, "\n", sep = "")
  cat("  content hash:   ", x$content_hash, "\n", sep = "")
  cat("  valid:          ", x$valid, "\n", sep = "")
  invisible(x)
}

#' @exportS3Method dplyr::collect
collect.entropia_conn <- function(x, ...) {
  ent_abort(
    "entropia_error_unsupported",
    c(
      "{.fn collect} on an {.cls entropia_conn} is not supported.",
      i = paste0(
        "Use {.fn entropia_collect} on a table object, ",
        "e.g. {.code entropia_collect(entropia_items(con))}."
      )
    )
  )
}
