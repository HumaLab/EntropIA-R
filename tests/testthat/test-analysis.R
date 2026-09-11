# Tests for Tasks 20-21 (analysis layer).
#
# Task 20: entropia_temporal_profile() and entropia_document_lengths().
# Task 21: entropia_entity_frequency(), entropia_topic_frequency() and
#          entropia_compare_collections().
# All are pure analysis helpers on collected tibbles (never lazy tables).
# Fixture-based tests collect fixture data first (entropia_collect() applies
# the datetime contract to single-table accessors); synthetic tibbles cover
# the pure counting maths and edge cases without any database.

ANAL_ASSET_PDF <- "33333333-3333-4333-8333-333333333331"
ANAL_ASSET_PAGE1 <- "33333333-3333-4333-8333-333333333332"
ANAL_ASSET_PAGE2 <- "33333333-3333-4333-8333-333333333333"
ANAL_ASSET_IMG <- "33333333-3333-4333-8333-333333333334"
ANAL_ASSET_AUDIO <- "33333333-3333-4333-8333-333333333335"

with_analysis_con <- function(name, f) {
  con <- ent_connect_fixture(name)
  on.exit(try(entropia_disconnect(con), silent = TRUE), add = TRUE)
  f(con)
}

# --- entropia_temporal_profile: fixture counts --------------------------------

test_that("temporal profile by month counts the fixture items", {
  with_analysis_con("full", function(con) {
    items <- entropia_collect(entropia_items(con))
    prof <- entropia_temporal_profile(items, created_at)
    expect_s3_class(prof, "tbl_df")
    expect_identical(names(prof), c("created_at", "n"))
    expect_equal(nrow(prof), 1L)
    expect_identical(prof$created_at, as.POSIXct("2026-01-01", tz = "UTC"))
    expect_identical(prof$n, 3L)
  })
})

test_that("temporal profile accepts a string date_var", {
  with_analysis_con("full", function(con) {
    items <- entropia_collect(entropia_items(con))
    prof <- entropia_temporal_profile(items, "created_at")
    expect_equal(nrow(prof), 1L)
    expect_identical(prof$created_at, as.POSIXct("2026-01-01", tz = "UTC"))
    expect_identical(prof$n, 3L)
  })
})

test_that("temporal profile buckets by second/hour/day/year on the fixture", {
  with_analysis_con("full", function(con) {
    items <- entropia_collect(entropia_items(con))
    secs <- entropia_temporal_profile(items, created_at, unit = "second")
    expect_equal(nrow(secs), 3L)
    expect_identical(
      secs$created_at,
      as.POSIXct(c("2026-01-15 12:01:00", "2026-01-15 12:03:00", "2026-01-15 12:05:00"), tz = "UTC")
    )
    expect_identical(secs$n, c(1L, 1L, 1L))

    hours <- entropia_temporal_profile(items, created_at, unit = "hour")
    expect_equal(nrow(hours), 1L)
    expect_identical(hours$created_at, as.POSIXct("2026-01-15 12:00:00", tz = "UTC"))
    expect_identical(hours$n, 3L)

    days <- entropia_temporal_profile(items, created_at, unit = "day")
    expect_identical(days$created_at, as.POSIXct("2026-01-15", tz = "UTC"))
    expect_identical(days$n, 3L)

    years <- entropia_temporal_profile(items, created_at, unit = "year")
    expect_identical(years$created_at, as.POSIXct("2026-01-01", tz = "UTC"))
    expect_identical(years$n, 3L)
  })
})

# --- entropia_temporal_profile: by grouping -----------------------------------

test_that("temporal profile breaks counts by a grouping column", {
  df <- tibble::tibble(
    when = as.POSIXct(c("2026-01-05", "2026-01-15", "2026-02-01"), tz = "UTC"),
    grp = c("a", "a", "b")
  )
  prof <- entropia_temporal_profile(df, when, by = grp)
  expect_identical(names(prof), c("grp", "when", "n"))
  expect_identical(prof$grp, c("a", "b"))
  expect_identical(prof$when, as.POSIXct(c("2026-01-01", "2026-02-01"), tz = "UTC"))
  expect_identical(prof$n, c(2L, 1L))
})

test_that("temporal profile by a character vector of grouping columns", {
  df <- tibble::tibble(
    when = as.POSIXct(c("2026-01-05", "2026-01-15", "2026-01-20"), tz = "UTC"),
    g1 = c("a", "a", "b"),
    g2 = c("x", "x", "x")
  )
  prof <- entropia_temporal_profile(df, when, by = c("g1", "g2"))
  expect_identical(names(prof), c("g1", "g2", "when", "n"))
  expect_identical(prof$n, c(2L, 1L))
})

test_that("temporal profile on the collected corpus groups by asset type", {
  with_analysis_con("full", function(con) {
    # the corpus join collects without a contract, so timestamps are raw ms;
    # convert with the datetime helper (the documented analysis workflow)
    cor <- dplyr::collect(entropia_corpus(con)) |>
      dplyr::mutate(asset_created_at = entropia_datetime(asset_created_at))
    prof <- entropia_temporal_profile(cor, asset_created_at, by = asset_type)
    expect_identical(prof$asset_type, c("audio", "image", "pdf"))
    expect_identical(prof$asset_created_at, rep(as.POSIXct("2026-01-01", tz = "UTC"), 3L))
    expect_identical(prof$n, c(1L, 1L, 3L))
  })
})

# --- entropia_temporal_profile: units, NA, typing, errors ----------------------

test_that("temporal profile week/quarter units bucket on synthetic dates", {
  df <- tibble::tibble(
    when = as.POSIXct(c("2026-01-15", "2026-01-17", "2026-01-19"), tz = "UTC")
  )
  wk <- entropia_temporal_profile(df, when, unit = "week")
  # weeks start on Monday: the 15th/17th fall in the week of the 12th
  expect_identical(wk$when, as.POSIXct(c("2026-01-12", "2026-01-19"), tz = "UTC"))
  expect_identical(wk$n, c(2L, 1L))

  dfq <- tibble::tibble(
    when = as.POSIXct(c("2026-01-15", "2026-04-02", "2026-04-10"), tz = "UTC")
  )
  q <- entropia_temporal_profile(dfq, when, unit = "quarter")
  expect_identical(q$when, as.POSIXct(c("2026-01-01", "2026-04-01"), tz = "UTC"))
  expect_identical(q$n, c(1L, 2L))
})

test_that("temporal profile drops NA timestamps but keeps NA grouping levels", {
  df <- tibble::tibble(
    when = as.POSIXct(c("2026-01-05", NA, "2026-01-15"), tz = "UTC")
  )
  prof <- entropia_temporal_profile(df, when)
  expect_equal(nrow(prof), 1L)
  expect_identical(prof$n, 2L)

  # an NA in the grouping column is its own group (dplyr semantics); NA groups
  # sort last in arrange()
  df2 <- tibble::tibble(
    when = as.POSIXct(c("2026-01-05", "2026-01-15", "2026-02-01"), tz = "UTC"),
    grp = c("a", NA_character_, "b")
  )
  prof2 <- entropia_temporal_profile(df2, when, by = grp)
  expect_identical(prof2$grp, c("a", "b", NA))
  expect_identical(prof2$n, c(1L, 1L, 1L))
})

test_that("temporal profile accepts a Date date_var", {
  df <- tibble::tibble(when = as.Date(c("2026-01-05", "2026-01-15")))
  prof <- entropia_temporal_profile(df, when)
  expect_equal(nrow(prof), 1L)
  expect_identical(prof$when, as.POSIXct("2026-01-01", tz = "UTC"))
  expect_identical(prof$n, 2L)
})

test_that("temporal profile returns an empty result for zero-row input", {
  df <- tibble::tibble(
    when = as.POSIXct(character(), tz = "UTC"),
    grp = character()
  )
  prof <- entropia_temporal_profile(df, when, by = grp)
  expect_equal(nrow(prof), 0L)
  expect_identical(names(prof), c("grp", "when", "n"))
  expect_identical(prof$n, integer())
})

test_that("temporal profile validates date_var typing", {
  cls <- "entropia_error_invalid_argument"
  # numeric (raw ms) is not a typed timestamp -- direct users to the helpers
  df <- tibble::tibble(t = c(1, 2, 3))
  expect_error(entropia_temporal_profile(df, t), class = cls)
  # character column is not a timestamp
  dfc <- tibble::tibble(t = c("a", "b"))
  expect_error(entropia_temporal_profile(dfc, t), class = cls)
})

test_that("temporal profile validates unit, columns, input and reserved names", {
  cls <- "entropia_error_invalid_argument"
  df <- tibble::tibble(
    when = as.POSIXct(c("2026-01-05", "2026-01-15"), tz = "UTC"),
    n = c(1, 2)
  )
  expect_error(entropia_temporal_profile(df, when, unit = "bogus"), class = cls)
  expect_error(entropia_temporal_profile(df, when, unit = c("month", "day")), class = cls)
  expect_error(entropia_temporal_profile(df, nope), class = cls)
  expect_error(entropia_temporal_profile(df, when, by = nope), class = cls)
  expect_error(entropia_temporal_profile(df, when, by = n), class = cls)
  expect_error(entropia_temporal_profile(df, c(when, n)), class = cls)
  # a lazy table is not a data.frame
  with_analysis_con("full", function(con) {
    expect_error(entropia_temporal_profile(entropia_items(con), created_at), class = cls)
  })
})

# --- entropia_document_lengths: fixture counts ---------------------------------

test_that("document lengths match the fixture's stripped texts", {
  with_analysis_con("full", function(con) {
    txt <- dplyr::collect(entropia_text(con))
    lens <- entropia_document_lengths(txt)
    expect_s3_class(lens, "tbl_df")
    expect_identical(names(lens), c(names(txt), "n_chars", "n_words"))
    expect_equal(nrow(lens), 5L)

    row <- function(id) lens[lens$id == id, ]
    expect_identical(row(ANAL_ASSET_PDF)$n_chars, 50L) # leading space survives marker strip
    expect_identical(row(ANAL_ASSET_PDF)$n_words, 9L)
    expect_identical(row(ANAL_ASSET_PAGE1)$n_chars, 54L)
    expect_identical(row(ANAL_ASSET_PAGE1)$n_words, 7L)
    expect_identical(row(ANAL_ASSET_AUDIO)$n_chars, 23L)
    expect_identical(row(ANAL_ASSET_AUDIO)$n_words, 4L)
    # assets with no text layer keep the row with NA counts
    expect_true(is.na(row(ANAL_ASSET_PAGE2)$n_chars))
    expect_true(is.na(row(ANAL_ASSET_PAGE2)$n_words))
    expect_true(is.na(row(ANAL_ASSET_IMG)$n_chars))
    expect_true(is.na(row(ANAL_ASSET_IMG)$n_words))
  })
})

test_that("document lengths works with a custom text column", {
  df <- tibble::tibble(id = c(1, 2, 3), content = c("uno dos", "tres", NA_character_))
  lens <- entropia_document_lengths(df, content)
  expect_identical(lens$n_chars, c(7L, 4L, NA_integer_))
  expect_identical(lens$n_words, c(2L, 1L, NA_integer_))
})

test_that("document lengths counts empty and whitespace-only text as zero", {
  df <- tibble::tibble(text = c("", "   ", "palabra"))
  lens <- entropia_document_lengths(df)
  expect_identical(lens$n_chars, c(0L, 3L, 7L))
  expect_identical(lens$n_words, c(0L, 0L, 1L))
})

test_that("document lengths collapses runs of spaces and keeps punctuation attached", {
  df <- tibble::tibble(text = c("dos   palabras", "Compa<U+00F1>eros, a la huelga"))
  lens <- entropia_document_lengths(df)
  expect_identical(lens$n_words, c(2L, 4L))
})

test_that("document lengths validates input, column and reserved names", {
  cls <- "entropia_error_invalid_argument"
  df <- tibble::tibble(text = "hola", n_chars = 1)
  expect_error(entropia_document_lengths(df), class = cls)
  expect_error(entropia_document_lengths(tibble::tibble(a = "x"), text_var = nope), class = cls)
  expect_error(entropia_document_lengths(c("a", "b")), class = cls)
  # a list-column (e.g. parsed JSON) is not plain text
  lf <- tibble::tibble(text = list(list(a = 1), list(b = 2)))
  expect_error(entropia_document_lengths(lf), class = cls)
})

# --- entropia_entity_frequency ------------------------------------------------

test_that("entity frequency counts the fixture entities by type", {
  with_analysis_con("full", function(con) {
    entities <- entropia_collect(entropia_entities(con))
    freq <- entropia_entity_frequency(entities)
    expect_s3_class(freq, "tbl_df")
    expect_identical(names(freq), c("entity_type", "value", "n"))
    expect_equal(nrow(freq), 3L)
    expect_identical(freq$entity_type, c("organization", "person", "place"))
    expect_identical(freq$value, c("Sindicato Ferroviario", "Juan P<U+00E9>rez", "Plaza de Mayo"))
    expect_identical(freq$n, c(1L, 1L, 1L))
  })
})

test_that("entity frequency counts duplicates and orders ties by value", {
  df <- tibble::tibble(
    entity_type = c("person", "person", "person", "place", "place"),
    value = c("Juan", "Juan", "Ana", "Madrid", "Madrid")
  )
  freq <- entropia_entity_frequency(df)
  expect_identical(freq$entity_type, c("person", "person", "place"))
  expect_identical(freq$value, c("Juan", "Ana", "Madrid"))
  expect_identical(freq$n, c(2L, 1L, 2L))
})

test_that("entity frequency breaks counts by collection when joined", {
  with_analysis_con("full", function(con) {
    entities <- entropia_collect(entropia_entities(con))
    items <- dplyr::select(
      entropia_collect(entropia_items(con)),
      item_id = "id", "collection_id"
    )
    colls <- dplyr::select(
      entropia_collect(entropia_collections(con)),
      collection_id = "id", collection_name = "name"
    )
    joined <- entities |>
      dplyr::left_join(items, by = "item_id") |>
      dplyr::left_join(colls, by = "collection_id")
    freq <- entropia_entity_frequency(joined, by = collection_name)
    expect_identical(names(freq), c("collection_name", "entity_type", "value", "n"))
    expect_equal(nrow(freq), 3L)
    expect_true(all(freq$collection_name == "Archivo de prueba"))
  })
})

test_that("entity frequency groups by a character-vector by column", {
  df <- tibble::tibble(
    entity_type = c("person", "person", "person"),
    value = c("Juan", "Juan", "Ana"),
    collection_name = c("A", "A", "B")
  )
  freq <- entropia_entity_frequency(df, by = "collection_name")
  expect_identical(names(freq), c("collection_name", "entity_type", "value", "n"))
  expect_identical(freq$collection_name, c("A", "B"))
  expect_identical(freq$value, c("Juan", "Ana"))
  expect_identical(freq$n, c(2L, 1L))
})

test_that("entity frequency counts soft-deleted rows when the input carries them", {
  with_analysis_con("full", function(con) {
    entities <- entropia_collect(entropia_entities(con, include_deleted = TRUE))
    freq <- entropia_entity_frequency(entities)
    expect_equal(nrow(freq), 4L)
    person_rows <- freq[freq$entity_type == "person", ]
    expect_identical(person_rows$value, c("Juan P<U+00E9>rez", "Persona Borrada"))
  })
})

test_that("entity frequency returns an empty result for zero-row input", {
  df <- tibble::tibble(entity_type = character(), value = character())
  freq <- entropia_entity_frequency(df)
  expect_equal(nrow(freq), 0L)
  expect_identical(names(freq), c("entity_type", "value", "n"))
  expect_identical(freq$n, integer())
})

test_that("entity frequency validates input, columns and reserved names", {
  cls <- "entropia_error_invalid_argument"
  expect_error(entropia_entity_frequency(c("a", "b")), class = cls)
  expect_error(entropia_entity_frequency(tibble::tibble(a = 1)), class = cls)
  df <- tibble::tibble(entity_type = "person", value = "Juan", n = 1)
  expect_error(entropia_entity_frequency(df, by = n), class = cls)
  df2 <- tibble::tibble(entity_type = "person", value = "Juan", grp = "x")
  expect_error(entropia_entity_frequency(df2, by = nope), class = cls)
  # a lazy table is not a data.frame
  with_analysis_con("full", function(con) {
    expect_error(entropia_entity_frequency(entropia_entities(con)), class = cls)
  })
})

# --- entropia_topic_frequency -------------------------------------------------

test_that("topic frequency counts items per topic on the fixture", {
  with_analysis_con("full", function(con) {
    joined <- dplyr::left_join(
      entropia_collect(entropia_item_topics(con)),
      entropia_collect(entropia_topics(con)),
      by = c("topic_id" = "id")
    )
    freq <- entropia_topic_frequency(joined)
    expect_s3_class(freq, "tbl_df")
    expect_identical(names(freq), c("name", "n"))
    expect_equal(nrow(freq), 2L)
    expect_identical(freq$name, c("HUELGA", "SINDICATO"))
    expect_identical(freq$n, c(1L, 1L))
  })
})

test_that("topic frequency orders by count descending then name", {
  df <- tibble::tibble(
    name = c("HUELGA", "HUELGA", "HUELGA", "SINDICATO", "SINDICATO", "ARCHIVO")
  )
  freq <- entropia_topic_frequency(df)
  expect_identical(freq$name, c("HUELGA", "SINDICATO", "ARCHIVO"))
  expect_identical(freq$n, c(3L, 2L, 1L))
})

test_that("topic frequency breaks counts by an extra grouping column", {
  df <- tibble::tibble(
    name = c("HUELGA", "HUELGA", "SINDICATO"),
    collection_name = c("A", "A", "A")
  )
  freq <- entropia_topic_frequency(df, by = collection_name)
  expect_identical(names(freq), c("collection_name", "name", "n"))
  expect_identical(freq$name, c("HUELGA", "SINDICATO"))
  expect_identical(freq$n, c(2L, 1L))
})

test_that("topic frequency validates input, column and reserved names", {
  cls <- "entropia_error_invalid_argument"
  expect_error(entropia_topic_frequency(tibble::tibble(topic = "x")), class = cls)
  expect_error(entropia_topic_frequency(c("a")), class = cls)
  df <- tibble::tibble(name = "HUELGA", n = 1)
  expect_error(entropia_topic_frequency(df, by = n), class = cls)
  with_analysis_con("full", function(con) {
    # lazy input, and collected item_topics without a joined topic name
    expect_error(entropia_topic_frequency(entropia_item_topics(con)), class = cls)
    expect_error(
      entropia_topic_frequency(entropia_collect(entropia_item_topics(con))),
      class = cls
    )
  })
})

# --- entropia_compare_collections ---------------------------------------------

test_that("compare collections summarises the collected corpus", {
  with_analysis_con("full", function(con) {
    cor <- dplyr::collect(entropia_corpus(con))
    cmp <- entropia_compare_collections(cor)
    expect_s3_class(cmp, "tbl_df")
    expect_identical(names(cmp), c("collection_id", "collection_name", "n_items", "n_assets", "n"))
    expect_equal(nrow(cmp), 1L)
    expect_identical(cmp$collection_name, "Archivo de prueba")
    expect_identical(cmp$n_items, 3L)
    expect_identical(cmp$n_assets, 5L)
    expect_identical(cmp$n, 5L)
  })
})

test_that("compare collections counts distinct ids per group", {
  df <- tibble::tibble(
    collection_name = c("A", "A", "B", "B", "B"),
    item_id = c("i1", "i1", "i2", "i2", "i3"),
    asset_id = c("a1", "a2", "a3", "a4", "a5")
  )
  cmp <- entropia_compare_collections(df)
  expect_identical(cmp$collection_name, c("A", "B"))
  expect_identical(cmp$n_items, c(1L, 2L))
  expect_identical(cmp$n_assets, c(2L, 3L))
  expect_identical(cmp$n, c(2L, 3L))
})

test_that("compare collections groups by a custom collection column", {
  df <- tibble::tibble(col = c("A", "A", "B"), item_id = c("i1", "i2", "i3"))
  cmp <- entropia_compare_collections(df, by = col)
  expect_identical(names(cmp), c("col", "n_items", "n"))
  expect_identical(cmp$col, c("A", "B"))
  expect_identical(cmp$n_items, c(2L, 1L))
  expect_identical(cmp$n, c(2L, 1L))
})

test_that("compare collections without id columns reports row counts only", {
  df <- tibble::tibble(collection_name = c("A", "A", "B"))
  cmp <- entropia_compare_collections(df)
  expect_identical(names(cmp), c("collection_name", "n"))
  expect_identical(cmp$collection_name, c("A", "B"))
  expect_identical(cmp$n, c(2L, 1L))
})

test_that("compare collections returns an empty result for zero-row input", {
  df <- tibble::tibble(
    collection_name = character(), item_id = character(), asset_id = character()
  )
  cmp <- entropia_compare_collections(df)
  expect_equal(nrow(cmp), 0L)
  expect_identical(names(cmp), c("collection_name", "n_items", "n_assets", "n"))
  expect_identical(cmp$n, integer())
})

test_that("compare collections validates input, by and reserved names", {
  cls <- "entropia_error_invalid_argument"
  expect_error(entropia_compare_collections(tibble::tibble(a = 1)), class = cls)
  expect_error(entropia_compare_collections(c("a")), class = cls)
  df <- tibble::tibble(collection_name = "A", item_id = "i1", n_items = 1)
  expect_error(entropia_compare_collections(df), class = cls)
  df2 <- tibble::tibble(collection_name = "A", n = 1)
  expect_error(entropia_compare_collections(df2, by = n), class = cls)
  df3 <- tibble::tibble(a = "x", b = "y")
  expect_error(entropia_compare_collections(df3, by = c(a, b)), class = cls)
  # a lazy table is not a data.frame
  with_analysis_con("full", function(con) {
    expect_error(entropia_compare_collections(entropia_corpus(con)), class = cls)
  })
})
