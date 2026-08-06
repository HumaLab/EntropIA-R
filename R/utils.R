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

# Safely read an attribute with a default. Attributes may be missing on
# hand-built objects, so never index them blindly.
ent_attr <- function(x, name, default = NA_character_) {
  out <- attr(x, name, exact = TRUE)
  if (is.null(out)) default else out
}

# Does `path` begin with the SQLite header magic?
ent_is_sqlite_header <- function(path) {
  f <- file(path, "rb")
  on.exit(close(f), add = TRUE)
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
