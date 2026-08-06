# Tests for Task 13 (entropia_collect + datetime/JSON/BLOB typing).
#
# entropia_collect() materialises a lazy tbl_sql and applies the column
# contract from inst/schemas/manifest.json: epoch timestamps -> POSIXct,
# JSON-in-TEXT -> list-columns, BLOB columns pass through as raw vectors.
# The exported entropia_datetime()/entropia_datetime_s()/entropia_datetime_auto()
# helpers are the pure conversions; ent_datetime_iso() handles the ISO-8601
# strings found inside JSON columns (items.metadata.importedAt).
# Fixture timestamps derive from BASE_S = 1768478400 (2026-01-15 12:00:00 UTC).

with_collect_con <- function(name, f) {
  con <- ent_connect_fixture(name)
  on.exit(try(entropia_disconnect(con), silent = TRUE), add = TRUE)
  f(con)
}

# --- exported datetime helpers ----------------------------------------------

test_that("entropia_datetime converts epoch milliseconds to POSIXct", {
  out <- entropia_datetime(c(1768478400000, 1768478460000, 1768482000000))
  expect_s3_class(out, "POSIXct")
  expect_equal(
    out,
    as.POSIXct(
      c("2026-01-15 12:00:00", "2026-01-15 12:01:00", "2026-01-15 13:00:00"),
      tz = "UTC"
    )
  )
})

test_that("entropia_datetime_s converts epoch seconds to POSIXct", {
  out <- entropia_datetime_s(c(1768478400, 1768479000))
  expect_equal(
    out,
    as.POSIXct(c("2026-01-15 12:00:00", "2026-01-15 12:10:00"), tz = "UTC")
  )
})

test_that("entropia_datetime_auto guards both magnitudes", {
  # below 1e12 -> epoch seconds
  expect_equal(
    entropia_datetime_auto(1768478400),
    as.POSIXct("2026-01-15 12:00:00", tz = "UTC")
  )
  # at/above 1e12 -> epoch milliseconds
  expect_equal(
    entropia_datetime_auto(1768478400000),
    as.POSIXct("2026-01-15 12:00:00", tz = "UTC")
  )
})

test_that("datetime helpers accept integer64 as RSQLite returns it", {
  skip_if_not_installed("bit64")
  expect_equal(
    entropia_datetime(bit64::as.integer64(1768478460000)),
    as.POSIXct("2026-01-15 12:01:00", tz = "UTC")
  )
  expect_equal(
    entropia_datetime_s(bit64::as.integer64(1768479000)),
    as.POSIXct("2026-01-15 12:10:00", tz = "UTC")
  )
})

test_that("datetime helpers pass POSIXct through and reject bad input", {
  dt <- as.POSIXct("2026-01-15 12:00:00", tz = "UTC")
  expect_equal(entropia_datetime(dt), dt)
  expect_error(
    entropia_datetime("not-a-time"),
    class = "entropia_error_invalid_argument"
  )
  expect_error(
    entropia_datetime_auto(TRUE),
    class = "entropia_error_invalid_argument"
  )
})

test_that("datetime helpers accept numeric character strings", {
  ms <- "1768478400000"
  s <- "1768478400"
  expect_equal(entropia_datetime(ms), entropia_datetime(as.numeric(ms)))
  expect_equal(entropia_datetime_s(s), entropia_datetime_s(as.numeric(s)))
  expect_equal(entropia_datetime_auto(s), entropia_datetime_auto(as.numeric(s)))
  expect_equal(entropia_datetime_auto(ms), entropia_datetime_auto(as.numeric(ms)))
})

test_that("datetime_s and datetime_auto pass POSIXct through", {
  dt <- as.POSIXct("2026-01-15 12:00:00", tz = "UTC")
  expect_equal(entropia_datetime_s(dt), dt)
  expect_equal(entropia_datetime_auto(dt), dt)
})

test_that("entropia_collect rejects non-lazy inputs", {
  expect_error(entropia_collect(1:3), class = "entropia_error_invalid_argument")
  expect_error(
    entropia_collect(tibble::tibble(a = 1)),
    class = "entropia_error_invalid_argument"
  )
})

# --- ISO-8601 inside JSON metadata -------------------------------------------

test_that("ISO-8601 strings inside metadata parse to POSIXct", {
  with_collect_con("full", function(con) {
    items <- entropia_collect(entropia_items(con))
    imp <- items$metadata[[1]][["__entropia_file_metadata"]][["importedAt"]]
    expect_equal(imp, "2026-01-15T12:05:00Z")
    dt <- entropiaR:::ent_datetime_iso(imp)
    expect_s3_class(dt, "POSIXct")
    expect_equal(dt, as.POSIXct("2026-01-15 12:05:00", tz = "UTC"))
  })
})

test_that("ent_datetime_iso handles fractional seconds", {
  dt <- entropiaR:::ent_datetime_iso("2026-01-15T12:05:00.500Z")
  expect_equal(as.numeric(dt), 1768478700.5, tolerance = 1e-6)
})

# --- JSON parse shapes via entropia_collect ---------------------------------

test_that("metadata object parses to a named list-column", {
  with_collect_con("full", function(con) {
    items <- entropia_collect(entropia_items(con))
    expect_true(is.list(items$metadata))
    m1 <- items$metadata[[1]]
    expect_true(is.list(m1) && !is.data.frame(m1))
    expect_named(m1, c("__entropia_file_metadata", "page_count"))
    expect_equal(m1$page_count, 2L)
    expect_equal(m1[["__entropia_file_metadata"]]$original_name, "manifiesto.pdf")
    # third item has no metadata -> NA
    expect_equal(items$metadata[[3]], NA_character_)
  })
})

test_that("segments array parses to a data.frame list-column", {
  with_collect_con("full", function(con) {
    trx <- entropia_collect(entropia_transcriptions(con))
    seg <- trx$segments[[1]]
    expect_true(is.data.frame(seg))
    expect_named(seg, c("start_ms", "end_ms", "text"))
    expect_equal(nrow(seg), 2L)
    expect_equal(seg$text, c("Compañeros", "a la huelga"))
  })
})

test_that("sources array parses to a data.frame list-column", {
  with_collect_con("full", function(con) {
    msgs <- entropia_collect(entropia_rag_messages(con))
    src <- msgs$sources[[2]] # assistant message carries citations
    expect_true(is.data.frame(src))
    expect_named(src, c("chunk_id", "text", "score"))
    expect_equal(nrow(src), 1L)
    # user message has no sources -> NA
    expect_equal(msgs$sources[[1]], NA_character_)
  })
})

test_that("llm_results.result object parses to a named list-column", {
  with_collect_con("full", function(con) {
    res <- entropia_collect(entropia_llm_results(con))
    r1 <- res$result[[1]]
    expect_true(is.list(r1) && !is.data.frame(r1))
    expect_equal(r1$summary, "Documento sobre la huelga general.")
    expect_equal(r1$tags, c("historia", "movimiento-obrero"))
  })
})

test_that("malformed JSON warns and yields NA rather than failing collect", {
  expect_warning(
    out <- entropiaR:::ent_parse_json_col('{"unclosed": '),
    "Malformed JSON"
  )
  expect_equal(out[[1]], NA_character_)
  # a valid cell alongside a malformed one still parses
  expect_warning(
    out2 <- entropiaR:::ent_parse_json_col(c('{"ok": 1}', '{"bad": ')),
    "Malformed JSON"
  )
  expect_equal(out2[[1]]$ok, 1)
  expect_equal(out2[[2]], NA_character_)
})

test_that("ent_parse_json_col is idempotent on already-parsed lists", {
  expect_equal(entropiaR:::ent_parse_json_col(list(a = 1)), list(a = 1))
})

test_that("malformed JSON with invalid UTF-8 bytes warns instead of crashing", {
  # A malformed JSON cell carrying a byte that is not valid UTF-8 used to
  # crash the cli warning formatter (ansi_strwrap) with "invalid multibyte
  # string"; ent_sanitize_msg() replaces the bad byte so the tolerant
  # warn-and-NA posture holds on real corpus content.
  bad <- rawToChar(as.raw(c(0x7b, 0x22, 0x61, 0x22, 0x3a, 0x20, 0xe9, 0x7d)))
  expect_warning(
    out <- entropiaR:::ent_parse_json_col(bad),
    "Malformed JSON"
  )
  expect_equal(out[[1]], NA_character_)
  # a valid cell alongside the invalid one still parses
  expect_warning(
    out2 <- entropiaR:::ent_parse_json_col(c('{"ok": 1}', bad)),
    "Malformed JSON"
  )
  expect_equal(out2[[1]]$ok, 1)
  expect_equal(out2[[2]], NA_character_)
})

test_that("ent_sanitize_msg guards null, NA and clean input", {
  expect_equal(entropiaR:::ent_sanitize_msg(NULL), "<unreadable JSON>")
  expect_equal(entropiaR:::ent_sanitize_msg(NA_character_), "<unreadable JSON>")
  expect_equal(entropiaR:::ent_sanitize_msg("plain"), "plain")
  bad <- rawToChar(as.raw(c(0xe9)))
  out <- entropiaR:::ent_sanitize_msg(bad)
  expect_type(out, "character")
  expect_false(is.na(out))
})

# --- BLOB passthrough ---------------------------------------------------------

test_that("BLOB columns pass through as raw vectors", {
  with_collect_con("full", function(con) {
    emb <- entropia_collect(entropia_embeddings(con, with_vector = TRUE))
    expect_true(is.list(emb$embedding))
    expect_true(all(vapply(emb$embedding, is.raw, logical(1))))
  })
})

# --- acceptance: correct POSIXct dates on ms and seconds fixtures -------------

test_that("entropia_collect on items yields correct POSIXct dates (ms fixture)", {
  with_collect_con("full", function(con) {
    items <- entropia_collect(entropia_items(con))
    expect_s3_class(items$created_at, "POSIXct")
    expect_equal(
      items$created_at,
      as.POSIXct(
        c("2026-01-15 12:01:00", "2026-01-15 12:03:00", "2026-01-15 12:05:00"),
        tz = "UTC"
      )
    )
    expect_equal(
      items$updated_at,
      as.POSIXct(
        c("2026-01-15 12:02:00", "2026-01-15 12:04:00", "2026-01-15 12:06:00"),
        tz = "UTC"
      )
    )
  })
})

test_that("datetime_auto yields correct POSIXct dates on both fixtures", {
  # entities/triples created_at are ms in full, seconds in legacy-seconds;
  # the magnitude guard must land on 2026-01-15 12:10:00 (offset 600s) either
  # way. The soft-deleted entity (offset 630) is excluded by default.
  with_collect_con("full", function(con) {
    ent <- entropia_collect(entropia_entities(con))
    base <- as.POSIXct("2026-01-15 12:00:00", tz = "UTC")
    offsets <- as.numeric(difftime(ent$created_at, base, units = "secs"))
    expect_true(all(offsets %in% c(600, 610, 620)))
  })
  with_collect_con("legacy-seconds", function(con) {
    ent <- entropia_collect(entropia_entities(con))
    base <- as.POSIXct("2026-01-15 12:00:00", tz = "UTC")
    offsets <- as.numeric(difftime(ent$created_at, base, units = "secs"))
    expect_true(all(offsets %in% c(600, 610, 620)))
  })
})
