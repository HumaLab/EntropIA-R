# v2 write API stubs (v1: read-only).
#
# entropiaR v1 is read-only by design. The database may be live in EntropIA
# (WAL journal) and is guarded by 81 triggers (48 sync capture + 33 activity),
# so no write surface is offered. The write verbs below exist so that code
# written against the v2 contract has a stable surface to fail on: every call
# aborts with `entropia_error_write_disabled` and actionable guidance, and
# entropia_connect(write = TRUE) rejects the request at the door.
#
# The v2 design (signatures, dry_run semantics, confirm gates, the
# INSERT ... ON CONFLICT policy that replaces INSERT OR REPLACE because rowid
# reassignment breaks FTS5) is documented in vignettes/administration.Rmd and
# in the plan's Write model.

# Shared stub error: the v2 contract is the same for every verb, so one helper
# raises the class and the guidance; each exported stub only adds its verb name.
ent_write_disabled <- function(verb) {
  ent_abort(
    "entropia_error_write_disabled",
    c(
      "{.fn {verb}} is not available in entropiaR v1.",
      i = paste0(
        "v1 is read-only: the database may be live in EntropIA (WAL) and is ",
        "protected by 81 sync/activity triggers."
      ),
      i = paste0(
        "Write support ships in v2, where you open the database for writing ",
        "with {.fn entropia_connect} ({.code path}, {.code write = TRUE})."
      ),
      i = "The v2 write design is documented in {.file vignettes/administration.Rmd}."
    )
  )
}

#' Insert rows (v2 contract; errors in v1)
#'
#' The write API is designed for v2 and shipped in v1 as stubs that error with
#' class `entropia_error_write_disabled`. Every call aborts immediately with
#' guidance: v1 is read-only, and write support arrives in v2 via
#' `entropia_connect(path, write = TRUE)`.
#'
#' In v2, `entropia_insert()` inserts validated rows in one transaction,
#' generating UUIDv4 primary keys for rows that do not carry one. It never uses
#' `INSERT OR REPLACE` (rowid reassignment breaks FTS5). `dry_run = TRUE`
#' (default) validates against the column contract without touching the
#' database.
#'
#' @param con An EntropIA connection.
#' @param table Table name.
#' @param data Data to insert (data frame/tibble).
#' @param dry_run Logical. In v2, validate without writing when `TRUE` (default).
#' @return Never returns: aborts with `entropia_error_write_disabled`.
#' @examples
#' con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
#'   package = "entropiaR"))
#' err <- tryCatch(entropia_insert(con, "items", data.frame(id = "x")), error = identity)
#' class(err)          # "entropia_error_write_disabled"
#' conditionMessage(err)
#' entropia_disconnect(con)
#' @export
entropia_insert <- function(con, table, data, dry_run = TRUE) {
  ent_write_disabled("entropia_insert")
}

#' Update rows (v2 contract; errors in v1)
#'
#' The write API is designed for v2 and shipped in v1 as stubs that error with
#' class `entropia_error_write_disabled`. Every call aborts immediately with
#' guidance: v1 is read-only, and write support arrives in v2 via
#' `entropia_connect(path, write = TRUE)`.
#'
#' In v2, `entropia_update()` updates rows matched by `by` (required) inside a
#' transaction and never rewrites primary keys.
#'
#' @param con An EntropIA connection.
#' @param table Table name.
#' @param data Data to write.
#' @param by Column name(s) identifying the rows to update (required in v2).
#' @param dry_run Logical. In v2, validate without writing when `TRUE` (default).
#' @return Never returns: aborts with `entropia_error_write_disabled`.
#' @examples
#' con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
#'   package = "entropiaR"))
#' err <- tryCatch(entropia_update(con, "items", data.frame(id = "x"), by = "id"),
#'   error = identity)
#' class(err)          # "entropia_error_write_disabled"
#' conditionMessage(err)
#' entropia_disconnect(con)
#' @export
entropia_update <- function(con, table, data, by, dry_run = TRUE) {
  ent_write_disabled("entropia_update")
}

#' Upsert rows (v2 contract; errors in v1)
#'
#' The write API is designed for v2 and shipped in v1 as stubs that error with
#' class `entropia_error_write_disabled`. Every call aborts immediately with
#' guidance: v1 is read-only, and write support arrives in v2 via
#' `entropia_connect(path, write = TRUE)`.
#'
#' In v2, `entropia_upsert()` implements upserts as
#' `INSERT ... ON CONFLICT(id) DO UPDATE` — never `INSERT OR REPLACE`, whose
#' rowid reassignment would break the contentless FTS5 tables.
#'
#' @param con An EntropIA connection.
#' @param table Table name.
#' @param data Data to insert or update.
#' @param by Column name(s) identifying the conflict key (required in v2).
#' @param dry_run Logical. In v2, validate without writing when `TRUE` (default).
#' @return Never returns: aborts with `entropia_error_write_disabled`.
#' @examples
#' con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
#'   package = "entropiaR"))
#' err <- tryCatch(entropia_upsert(con, "items", data.frame(id = "x"), by = "id"),
#'   error = identity)
#' class(err)          # "entropia_error_write_disabled"
#' conditionMessage(err)
#' entropia_disconnect(con)
#' @export
entropia_upsert <- function(con, table, data, by, dry_run = TRUE) {
  ent_write_disabled("entropia_upsert")
}

#' Delete rows (v2 contract; errors in v1)
#'
#' The write API is designed for v2 and shipped in v1 as stubs that error with
#' class `entropia_error_write_disabled`. Every call aborts immediately with
#' guidance: v1 is read-only, and write support arrives in v2 via
#' `entropia_connect(path, write = TRUE)`.
#'
#' In v2, `entropia_delete()` deletes rows matched by `filter` inside a
#' transaction. A full-table delete is refused unless `all = TRUE`, and every
#' delete requires `confirm = TRUE`.
#'
#' @param con An EntropIA connection.
#' @param table Table name.
#' @param filter A predicate identifying the rows to delete (required in v2; a
#'   full-table delete needs `all = TRUE`).
#' @param all Logical. In v2, permit a full-table delete when `TRUE` (default
#'   `FALSE`).
#' @param confirm Logical. In v2, must be `TRUE` for a delete to run.
#' @return Never returns: aborts with `entropia_error_write_disabled`.
#' @examples
#' con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
#'   package = "entropiaR"))
#' err <- tryCatch(entropia_delete(con, "items", id == "x", confirm = TRUE),
#'   error = identity)
#' class(err)          # "entropia_error_write_disabled"
#' conditionMessage(err)
#' entropia_disconnect(con)
#' @export
entropia_delete <- function(con, table, filter, all = FALSE, confirm = FALSE) {
  ent_write_disabled("entropia_delete")
}
