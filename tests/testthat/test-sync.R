# Tests for Task 8: sync-metadata surface.
#
# entropia_sync_info() returns the whitelisted sync_meta keys typed; the lazy
# accessors expose sync_row_versions and sync_conflicts. app_settings is never
# surfaced raw (secret keys excluded). All fixtures come from ent_fixture()
# temp copies; the reference corpus is never opened.

# The documented sync_conflicts.reason enum (EntropIA-Cloud/docs/DESIGN.md).
ent_conflict_reasons <- c(
  "lww_lost", "parent_deleted", "unique_collision", "apply_error",
  "schema_drift", "blob_missing", "blob_hash_mismatch"
)

with_sync_con <- function(name, f) {
  con <- ent_connect_fixture(name)
  on.exit(try(entropia_disconnect(con), silent = TRUE), add = TRUE)
  f(con)
}

# --- entropia_sync_info ------------------------------------------------------

test_that("entropia_sync_info returns the whitelisted sync_meta keys typed", {
  with_sync_con("full", function(con) {
    si <- entropia_sync_info(con)
    expect_s3_class(si, "tbl_df")
    expect_identical(
      names(si),
      c(
        "device_id", "account_email", "server_url", "last_sync_at",
        "server_epoch", "triggers_version", "capture_enabled"
      )
    )
    expect_equal(nrow(si), 1L)
    expect_identical(si$device_id, "device-fixture")
    expect_identical(si$account_email, "fixture@entropia.example")
    expect_identical(si$server_url, "https://cloud.entropia.example")
    expect_s3_class(si$last_sync_at, "POSIXct")
    expect_identical(
      si$last_sync_at,
      as.POSIXct(1768479200, origin = "1970-01-01", tz = "UTC")
    )
    # server_epoch is a server/session identifier string on real databases
    # (a UUID), so it must stay character -- never coerced to a number.
    expect_identical(si$server_epoch, "c3f5e8a0-1111-4111-8111-111111111111")
    expect_type(si$server_epoch, "character")
    expect_identical(si$triggers_version, 2L)
    expect_true(si$capture_enabled)
  })
})

test_that("entropia_sync_info excludes non-whitelisted sync_meta keys", {
  with_sync_con("full", function(con) {
    si <- entropia_sync_info(con)
    # last_pull_seq is stored in sync_meta but is not on the whitelist.
    expect_false("last_pull_seq" %in% names(si))
  })
})

test_that("entropia_sync_info never surfaces app_settings secrets", {
  with_sync_con("full", function(con) {
    si <- entropia_sync_info(con)
    # app_settings holds *_api_key secrets; none of its keys or values may
    # appear in the typed sync surface.
    secret_keys <- c("openai_api_key", "openrouter_api_key")
    expect_false(any(secret_keys %in% names(si)))
    flat <- as.character(unlist(si))
    expect_false(any(grepl("secret-should-not-surface", flat)))
    expect_false(any(grepl("sk-|or-", flat)))
  })
})

test_that("entropia_sync_info reports typed NAs on a never-synced database", {
  with_sync_con("mini", function(con) {
    si <- entropia_sync_info(con)
    expect_equal(nrow(si), 1L)
    expect_identical(names(si), c(
      "device_id", "account_email", "server_url", "last_sync_at",
      "server_epoch", "triggers_version", "capture_enabled"
    ))
    expect_true(is.na(si$device_id))
    expect_true(is.na(si$last_sync_at))
    expect_s3_class(si$last_sync_at, "POSIXct")
    expect_true(is.na(si$server_epoch))
    expect_true(is.na(si$triggers_version))
    expect_true(is.na(si$capture_enabled))
  })
})

# --- entropia_sync_versions --------------------------------------------------

test_that("entropia_sync_versions is lazy and joins push down to SQL", {
  with_sync_con("full", function(con) {
    sv <- entropia_sync_versions(con)
    expect_s3_class(sv, "tbl_sql")
    expect_match(dbplyr::sql_render(sv), "sync_row_versions")
    # No collect() happens on construction: the class is lazy.

    # A filter + join stays in SQLite (no R-side row materialisation).
    items <- dplyr::tbl(con, "items")
    joined <- sv |>
      dplyr::filter(server_seq > 5L) |>
      dplyr::left_join(items, by = c("row_id" = "id"))
    sql <- dbplyr::sql_render(joined)
    expect_match(sql, "JOIN")
    expect_match(sql, "server_seq")
    expect_match(sql, "WHERE")
    expect_match(sql, "items")

    out <- dplyr::collect(joined)
    expect_true(all(out$server_seq > 5L))
    # The fixture's items row (server_seq 10) joins to ITEM_1.
    expect_true("Manifiesto de la huelga" %in% out$title)
  })
})

test_that("entropia_sync_versions exposes the versioning columns", {
  with_sync_con("full", function(con) {
    out <- dplyr::collect(entropia_sync_versions(con))
    expect_true(all(c("table_name", "row_id", "server_seq") %in% names(out)))
    expect_equal(nrow(out), 2L)
    expect_true(all(is.integer(out$server_seq)))
  })
})

# --- entropia_conflicts ------------------------------------------------------

test_that("entropia_conflicts is lazy and reasons are documented enum values", {
  with_sync_con("full", function(con) {
    cf <- entropia_conflicts(con)
    expect_s3_class(cf, "tbl_sql")
    expect_match(dbplyr::sql_render(cf), "sync_conflicts")

    out <- dplyr::collect(cf)
    expect_true(all(c(
      "id", "table_name", "row_id", "reason",
      "loser_payload", "winner_summary", "created_at",
      "acknowledged"
    ) %in% names(out)))
    expect_equal(nrow(out), 1L)
    # The fixture uses a documented enum value; the contract holds.
    expect_true(all(out$reason %in% ent_conflict_reasons))
    expect_identical(out$reason, "lww_lost")
    expect_identical(out$acknowledged, 0L)
  })
})

# --- error paths -------------------------------------------------------------

test_that("sync accessors raise stable classes on missing tables", {
  with_sync_con("mini", function(con) {
    # mini has no sync tables.
    expect_error(entropia_sync_versions(con),
      class = "entropia_error_table_missing"
    )
    expect_error(entropia_conflicts(con),
      class = "entropia_error_table_missing"
    )
  })
})

test_that("sync functions reject a closed connection", {
  con <- withr::with_options(
    list(entropiaR.schema_policy = "allow"),
    entropia_connect(ent_fixture("full"))
  )
  entropia_disconnect(con)
  expect_error(entropia_sync_info(con),
    class = "entropia_error_invalid_connection"
  )
  expect_error(entropia_sync_versions(con),
    class = "entropia_error_invalid_connection"
  )
  expect_error(entropia_conflicts(con),
    class = "entropia_error_invalid_connection"
  )
})
