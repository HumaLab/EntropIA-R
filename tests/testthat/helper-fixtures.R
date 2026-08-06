# Fixture helpers -----------------------------------------------------------
#
# Test fixtures live in tests/testthat/fixtures/ and are generated
# deterministically by data-raw/make_fixtures.R. Tests never read from
# data-test/entropia.sqlite (reference corpus only) and never mutate the
# checked-in fixture artifacts: every helper hands out a throw-away copy.
#
# Helpers provided here:
# - ent_fixture(name): path to a writable temp copy of fixture `name`
# - ent_connect_fixture(name): a connection to a temp copy of fixture `name`
#
# Fixture inventory: mini, full, legacy-pre0019, legacy-seconds,
# unknown-version, corrupt, notsqlite.

# Test helpers are defined here (helper-fixtures.R) but used across test-*.R
# files; declare them so static analysis (lintr object_usage) can resolve them.
utils::globalVariables(c("ent_fixture", "ent_connect_fixture", "ent_fixture_version"))

# Map of fixture name -> on-disk file inside tests/testthat/fixtures/.
ent_fixture_files <- function() {
  c(
    mini = "mini.sqlite",
    full = "full.sqlite",
    "legacy-pre0019" = "legacy-pre0019.sqlite",
    "legacy-seconds" = "legacy-seconds.sqlite",
    "unknown-version" = "unknown-version.sqlite",
    corrupt = "corrupt.sqlite",
    notsqlite = "notsqlite.txt"
  )
}

#' Path to a writable temporary copy of a fixture
#'
#' Copies the requested fixture out of `tests/testthat/fixtures/` into a
#' session temp file so that tests may freely mutate (or fail to open) it
#' without ever touching the deterministic source artifacts.
#'
#' @param name One of the fixture names (see [ent_fixture_files()]).
#' @return A path to a private temp copy of the fixture.
#' @keywords internal
ent_fixture <- function(name) {
  files <- ent_fixture_files()
  if (!name %in% names(files)) {
    stop(
      sprintf(
        "Unknown fixture '%s'. Available: %s",
        name, paste(names(files), collapse = ", ")
      ),
      call. = FALSE
    )
  }
  src <- testthat::test_path("fixtures", files[[name]])
  if (!file.exists(src)) {
    stop(
      sprintf(
        "Fixture '%s' not found at '%s'. Run data-raw/make_fixtures.R.",
        name, src
      ),
      call. = FALSE
    )
  }
  ext <- tools::file_ext(src)
  dest <- tempfile(
    pattern = paste0("entfix-", name, "-"),
    fileext = if (nzchar(ext)) paste0(".", ext) else ""
  )
  file.copy(src, dest, overwrite = TRUE)
  dest
}

#' Connect to a temporary copy of a fixture
#'
#' Returns a connection to a private temp copy of the named fixture. When the
#' package's typed `entropia_connect()` is available it is preferred; until it
#' lands (Task 4) the helper falls back to a read-only `DBI` connection so the
#' fixture infrastructure is testable in isolation.
#'
#' @param name One of the fixture names (see [ent_fixture_files()]).
#' @param policy Schema policy for the connection. Defaults to `"allow"` so
#'   fixture tests stay quiet about older/unknown fixture schemas; tests that
#'   exercise the compatibility layer pass the policy they mean to test.
#' @return A DBI connection (or `entropia_conn`).
#' @keywords internal
ent_connect_fixture <- function(name, policy = "allow", ...) {
  path <- ent_fixture(name)
  if (exists("entropia_connect", mode = "function")) {
    old <- options(entropiaR.schema_policy = policy)
    on.exit(options(old), add = TRUE)
    return(entropiaR::entropia_connect(path, ...))
  }
  DBI::dbConnect(RSQLite::SQLite(), path, flags = RSQLite::SQLITE_RO)
}

#' Read the schema head (MAX `_migrations.name`) from an open connection
#'
#' @param con An open DBI connection.
#' @return A single character string, or `NA_character_` if `_migrations` is
#'   missing.
#' @keywords internal
ent_fixture_version <- function(con) {
  if (!DBI::dbExistsTable(con, "_migrations")) {
    return(NA_character_)
  }
  DBI::dbGetQuery(con, "SELECT MAX(name) AS v FROM _migrations")$v
}
