# Internal helpers for entropiaR (unexported; ent_* naming convention).
#
# Shared across modules: error construction, file sanity checks,
# schema-version detection and the reproducibility content hash.

# SQLite header magic: the 16-byte signature every SQLite 3 database file
# begins with ("SQLite format 3" + NUL).
ent_sqlite_magic <- c(charToRaw("SQLite format 3"), as.raw(0))

# Abort with a stable error class and cli-formatted message.
ent_abort <- function(class, message, ..., .envir = parent.frame()) {
  cli::cli_abort(message, class = class, ..., .envir = .envir)
}

# Deprecation scaffolding: the package-wide call site for lifecycle
# deprecations, so future deprecations share one consistent wrapper instead of
# each function reaching for lifecycle directly. Not called in v1 (nothing is
# deprecated yet) but provided and documented so the mechanism is in place
# before the first deprecation lands. The env/user_env pair attributes the
# warning to the deprecated function's caller, per the lifecycle custom-wrapper
# guidance; the policy (one-release grace) is documented in the package help.
ent_deprecate <- function(when, what, with = NULL, details = NULL, id = NULL) {
  lifecycle::deprecate_warn(
    when = when,
    what = what,
    with = with,
    details = details,
    id = id,
    env = rlang::caller_env(),
    user_env = rlang::caller_env(2)
  )
}

# NULL-defaulting operator (rlang::`%||%` without the dependency).
`%||%` <- function(x, y) if (is.null(x)) y else x

# Sanitize a diagnostic string pulled from database content before it is
# interpolated into a cli message. The EntropIA corpus stores newspaper text
# in JSON-in-TEXT columns that can hold bytes which are not valid UTF-8
# (RSQLite returns them as-is); interpolating such a string into a cli message
# crashes the cli formatter (ansi_strwrap) with "invalid multibyte string".
# iconv() replaces the invalid bytes with "?", so the warning stays readable
# and the tolerant warn-and-NA posture is preserved.
ent_sanitize_msg <- function(m) {
  if (is.null(m) || length(m) == 0L || is.na(m)) {
    return("<unreadable JSON>")
  }
  out <- tryCatch(
    iconv(m, from = "UTF-8", to = "UTF-8", sub = "?"),
    error = function(e) NA_character_
  )
  if (is.na(out)) "<unreadable JSON>" else out
}

# Require a live entropiaR connection. Every exported function that takes a
# connection starts with this so the error message is stable and actionable.
ent_require_conn <- function(con) {
  ok <- tryCatch(DBI::dbIsValid(con), error = function(e) FALSE)
  if (!isTRUE(ok)) {
    ent_abort(
      "entropia_error_invalid_connection",
      c(
        "Argument {.arg con} must be an open connection.",
        i = "Create one with {.fn entropia_connect}."
      )
    )
  }
  invisible(con)
}

# Safely read an attribute with a default. Attributes may be missing on
# hand-built objects, so never index them blindly.
ent_attr <- function(x, name, default = NA_character_) {
  out <- attr(x, name, exact = TRUE)
  if (is.null(out)) default else out
}

# Does `path` begin with the SQLite header magic?
ent_is_sqlite_header <- function(path) {
  if (is.na(path) || !nzchar(path) || dir.exists(path)) {
    return(FALSE)
  }
  f <- tryCatch(file(path, "rb"), error = function(e) NULL)
  if (is.null(f)) {
    return(FALSE)
  }
  on.exit(try(close(f), silent = TRUE), add = TRUE)
  hdr <- readBin(f, "raw", n = length(ent_sqlite_magic))
  length(hdr) == length(ent_sqlite_magic) && identical(hdr, ent_sqlite_magic)
}

# Schema head: MAX(_migrations.name), NA when the table is absent.
ent_current_version <- function(con) {
  if (!DBI::dbExistsTable(con, "_migrations")) {
    return(NA_character_)
  }
  v <- DBI::dbGetQuery(con, "SELECT MAX(name) AS v FROM _migrations")$v
  if (is.null(v) || is.na(v)) NA_character_ else as.character(v)
}

# Reproducibility content hash: sha256 over the schema text (sqlite_master
# SQL) plus the _migrations rows. Cheap and stable -- it distinguishes schema
# state without hashing table data.
ent_content_hash <- function(con) {
  schema <- DBI::dbGetQuery(
    con,
    "SELECT type, name, sql FROM sqlite_master WHERE sql IS NOT NULL ORDER BY type, name"
  )
  mig <- tryCatch(
    DBI::dbGetQuery(con, "SELECT name, applied_at FROM _migrations ORDER BY name"),
    error = function(e) data.frame(name = character(0), applied_at = numeric(0))
  )
  canonical <- paste0(
    paste(schema$type, schema$name, schema$sql, sep = "|", collapse = "\n"),
    "\n",
    paste(mig$name, mig$applied_at, sep = "|", collapse = "\n")
  )
  digest::digest(canonical, algo = "sha256", serialize = FALSE)
}
