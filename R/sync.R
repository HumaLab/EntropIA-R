# Sync-metadata surface (Task 8).
#
# Read-only views over the sync engine's bookkeeping tables:
#   entropia_sync_info()     -- whitelisted sync_meta keys, typed
#   entropia_sync_versions() -- lazy tbl_sql over sync_row_versions
#   entropia_conflicts()     -- lazy tbl_sql over sync_conflicts
#
# app_settings is deliberately NOT part of this surface: it stores API secrets
# (*_api_key) and the app itself blocks it from generic IPC. sync_info returns
# only the whitelisted keys below (the manifest's sync_meta_keys contract), so
# secrets can never leak through the typed surface.

# Whitelisted sync_meta keys and the R type each value coerces to. The set and
# order mirror the manifest's sync_meta_keys (the compatibility contract);
# secret-bearing keys never appear here.
#
# server_epoch is character, not integer: on real databases the app stores a
# server/session identifier string (a UUID), not a numeric epoch, so numeric
# coercion would silently produce NA.
ent_sync_info_spec <- function() {
  c(
    device_id = "character",
    account_email = "character",
    server_url = "character",
    last_sync_at = "datetime_ms",
    server_epoch = "character",
    triggers_version = "integer",
    capture_enabled = "logical"
  )
}

# The whitelist, sourced from the manifest's sync_meta_keys (the contract) with
# a fallback to the built-in spec so the function degrades gracefully if the
# manifest ever changes shape.
ent_sync_whitelist <- function() {
  mf <- tryCatch(ent_manifest(), error = function(e) NULL)
  keys <- if (!is.null(mf)) mf$sync_meta_keys else NULL
  if (is.null(keys)) names(ent_sync_info_spec()) else keys
}

# Coerce a raw sync_meta value (character) to its typed form. Unknown kinds
# fall back to character (forward compatibility: a new manifest key with no
# spec stays readable).
ent_sync_coerce <- function(raw, kind) {
  switch(kind,
    integer = as.integer(raw),
    logical = as.integer(raw) == 1L,
    datetime_ms = as.POSIXct(as.numeric(raw) / 1000, origin = "1970-01-01", tz = "UTC"),
    as.character(raw)
  )
}

# Typed NA for a missing whitelisted key, so the returned tibble keeps its
# column types even on a database that has never synced.
ent_sync_typed_na <- function(kind) {
  switch(kind,
    integer = NA_integer_,
    logical = NA,
    datetime_ms = as.POSIXct(NA_real_, origin = "1970-01-01", tz = "UTC"),
    NA_character_
  )
}

# Whitelisted sync_meta values as a typed named list (key -> value). Keys
# absent from sync_meta come back as typed NA.
ent_sync_info_values <- function(con) {
  spec <- ent_sync_info_spec()
  sm <- ent_sync_meta(con)
  keys <- ent_sync_whitelist()
  out <- lapply(keys, function(k) {
    raw <- sm[k]
    kind <- spec[[k]] %||% "character"
    if (length(raw) == 0L || is.na(raw) || !nzchar(raw)) {
      ent_sync_typed_na(kind)
    } else {
      ent_sync_coerce(raw, kind)
    }
  })
  names(out) <- keys
  out
}

#' Whitelisted sync settings as a typed tibble
#'
#' Reads the sync engine's `sync_meta` key/value table and returns only the
#' whitelisted keys -- the ones that describe sync identity and freshness --
#' coerced to their natural R types. `last_sync_at` (epoch milliseconds) is
#' returned as `POSIXct`; `server_epoch` stays character (the app stores a
#' server/session identifier string, not a numeric epoch); `triggers_version`
#' as an integer; `capture_enabled` as a logical.
#'
#' `app_settings` is never part of this surface: it stores API secrets
#' (`*_api_key`) and is deliberately not surfaced raw.
#'
#' @param con A connection returned by [entropia_connect()].
#' @return A one-row tibble with columns `device_id`, `account_email`,
#'   `server_url`, `last_sync_at`, `server_epoch`, `triggers_version` and
#'   `capture_enabled`. Keys absent from the database are `NA` of the correct
#'   type.
#' @examples
#' con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
#'   package = "entropiaR"
#' ))
#' entropia_sync_info(con)
#' entropia_disconnect(con)
#' @export
entropia_sync_info <- function(con) {
  ent_require_conn(con)
  tibble::as_tibble(ent_sync_info_values(con))
}

#' Sync row versions (lazy)
#'
#' A lazy [dplyr::tbl()] over `sync_row_versions`, which maps every synced row
#' `(table_name, row_id)` to the server sequence number it was last seen at.
#' The result is uncollected, so filtering, joining and aggregating happen in
#' SQLite; call `entropia_collect()` (or `dplyr::collect()`) to bring rows into
#' R.
#'
#' @param con A connection returned by [entropia_connect()].
#' @return A `tbl_sql` on `sync_row_versions`.
#' @examples
#' con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
#'   package = "entropiaR"
#' ))
#' entropia_collect(entropia_sync_versions(con))
#' entropia_disconnect(con)
#' @export
entropia_sync_versions <- function(con) {
  ent_require_conn(con)
  ent_require_columns(con, "sync_row_versions", c("table_name", "row_id", "server_seq"))
  dplyr::tbl(con, "sync_row_versions")
}

#' Sync conflicts (lazy)
#'
#' A lazy [dplyr::tbl()] over `sync_conflicts`. Each row records one conflict
#' the sync engine could not resolve automatically. `reason` is a documented
#' enum: `lww_lost` (lost the last-writer-wins race), `parent_deleted`,
#' `unique_collision`, `apply_error`, `schema_drift`, `blob_missing`,
#' `blob_hash_mismatch`. `created_at` is epoch milliseconds; `loser_payload`
#' and `winner_summary` are JSON text.
#'
#' @param con A connection returned by [entropia_connect()].
#' @return A `tbl_sql` on `sync_conflicts`.
#' @examples
#' con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
#'   package = "entropiaR"
#' ))
#' entropia_collect(entropia_conflicts(con))
#' entropia_disconnect(con)
#' @export
entropia_conflicts <- function(con) {
  ent_require_conn(con)
  ent_require_columns(
    con, "sync_conflicts",
    c(
      "id", "table_name", "row_id", "reason", "loser_payload",
      "winner_summary", "created_at", "acknowledged"
    )
  )
  dplyr::tbl(con, "sync_conflicts")
}
