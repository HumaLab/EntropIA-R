# Tests for Task 11 (research accessors).
#
# entropia_entities() is the only accessor with behaviour: it excludes
# soft-deleted rows (source = 'manual_deleted') by default and supports a
# confidence threshold, both pushed down to SQL. The remaining research
# accessors (triples/topics/item_topics/notes/annotations) are plain lazy
# reads over their raw tables. The full fixture carries one soft-deleted
# entity, both item-level and asset-scoped notes, and UPPERCASE topic names,
# so each contract point below is observable.
# All fixtures come from ent_fixture() (temp copies); never data-test/.

with_research_con <- function(name, f) {
  con <- ent_connect_fixture(name)
  on.exit(try(entropia_disconnect(con), silent = TRUE), add = TRUE)
  f(con)
}

# --- laziness ---------------------------------------------------------------

test_that("research accessors are lazy tbl_sql over their raw table", {
  with_research_con("full", function(con) {
    for (t in list(
      entropia_entities(con),
      entropia_triples(con),
      entropia_topics(con),
      entropia_item_topics(con),
      entropia_notes(con),
      entropia_annotations(con)
    )) {
      expect_s3_class(t, "tbl_sql")
      expect_false(inherits(t, "data.frame"))
      expect_true(is.na(nrow(t)))
    }
    expect_match(dbplyr::sql_render(entropia_entities(con)), "entities")
    expect_match(dbplyr::sql_render(entropia_triples(con)), "triples")
    expect_match(dbplyr::sql_render(entropia_topics(con)), "topics")
    expect_match(dbplyr::sql_render(entropia_item_topics(con)), "item_topics")
    expect_match(dbplyr::sql_render(entropia_notes(con)), "notes")
    expect_match(dbplyr::sql_render(entropia_annotations(con)), "annotations")
  })
})

test_that("research accessor row counts match the full fixture", {
  with_research_con("full", function(con) {
    expect_equal(nrow(dplyr::collect(entropia_entities(con))), 3L) # soft-deleted excluded
    expect_equal(nrow(dplyr::collect(entropia_triples(con))), 1L)
    expect_equal(nrow(dplyr::collect(entropia_topics(con))), 2L)
    expect_equal(nrow(dplyr::collect(entropia_item_topics(con))), 2L)
    expect_equal(nrow(dplyr::collect(entropia_notes(con))), 2L)
    expect_equal(nrow(dplyr::collect(entropia_annotations(con))), 1L)
  })
})

test_that("research accessor columns match the manifest contract", {
  with_research_con("full", function(con) {
    mf <- ent_manifest()
    for (t in c("entities", "triples", "topics", "item_topics", "notes", "annotations")) {
      got <- as.vector(dplyr::tbl_vars(ent_tbl(con, t)))
      want <- names(mf$tables[[t]]$columns)
      expect_identical(got, want, info = t)
    }
  })
})

# --- entities: soft-delete semantics ----------------------------------------

test_that("entities excludes soft-deleted rows by default, include_deleted keeps them", {
  with_research_con("full", function(con) {
    def <- dplyr::collect(entropia_entities(con))
    inc <- dplyr::collect(entropia_entities(con, include_deleted = TRUE))
    expect_equal(nrow(def), 3L)
    expect_equal(nrow(inc), 4L)
    expect_false(any(def$value == "Persona Borrada"))
    expect_true("Persona Borrada" %in% inc$value)
    expect_setequal(def$value, c("Juan Pérez", "Plaza de Mayo", "Sindicato Ferroviario"))
  })
})

test_that("entities soft-delete filter is pushed down to SQL", {
  with_research_con("full", function(con) {
    sql <- dbplyr::sql_render(entropia_entities(con))
    expect_match(sql, "WHERE")
    expect_match(sql, "manual_deleted")
    expect_match(sql, "source")
  })
})

test_that("entities min_confidence filters in SQL and composes with soft-delete", {
  with_research_con("full", function(con) {
    sql <- dbplyr::sql_render(entropia_entities(con, min_confidence = 0.9))
    expect_match(sql, "confidence")

    # 0.97 keeps only the 0.97 entity.
    out <- dplyr::collect(entropia_entities(con, min_confidence = 0.95))
    expect_equal(nrow(out), 1L)
    expect_identical(out$value, "Juan Pérez")

    # 0.9 keeps the three live entities; the soft-deleted 0.5 row stays out.
    out2 <- dplyr::collect(entropia_entities(con, min_confidence = 0.9))
    expect_equal(nrow(out2), 3L)

    # include_deleted + threshold brings the deleted 0.5 row back.
    out3 <- dplyr::collect(entropia_entities(con, include_deleted = TRUE, min_confidence = 0.5))
    expect_equal(nrow(out3), 4L)
  })
})

test_that("entities entity_type values and provenance columns surface", {
  with_research_con("full", function(con) {
    out <- dplyr::collect(entropia_entities(con))
    expect_setequal(out$entity_type, c("person", "place", "organization"))
    # Provenance columns (0009) are exposed.
    expect_true(all(c("source", "model_name") %in% names(out)))
    expect_true(all(out$source == "ner"))
    expect_true(all(out$model_name == "spacy-es"))
    # Confidence comes back numeric.
    expect_type(out$confidence, "double")
  })
})

test_that("entities rejects invalid include_deleted / min_confidence arguments", {
  cls <- "entropia_error_invalid_argument"
  with_research_con("full", function(con) {
    expect_error(entropia_entities(con, include_deleted = NA), class = cls)
    expect_error(entropia_entities(con, include_deleted = "yes"), class = cls)
    expect_error(entropia_entities(con, min_confidence = 2), class = cls)
    expect_error(entropia_entities(con, min_confidence = -0.1), class = cls)
    expect_error(entropia_entities(con, min_confidence = "high"), class = cls)
    expect_error(entropia_entities(con, min_confidence = c(0.5, 0.9)), class = cls)
  })
})

# --- entities: nullable asset_id ---------------------------------------------

test_that("entities asset_id is NULL (item-level) and exposed as NA", {
  with_research_con("full", function(con) {
    out <- dplyr::collect(entropia_entities(con, include_deleted = TRUE))
    expect_true("asset_id" %in% names(out))
    expect_true(all(is.na(out$asset_id)))
  })
})

# --- triples -----------------------------------------------------------------

test_that("triples carry subject/predicate/object and a nullable asset_id", {
  with_research_con("full", function(con) {
    out <- dplyr::collect(entropia_triples(con))
    expect_equal(nrow(out), 1L)
    expect_identical(out$subject, "Juan Pérez")
    expect_identical(out$predicate, "participo_en")
    expect_identical(out$object, "la huelga")
    expect_true(is.na(out$asset_id)) # item-level triple
  })
})

# --- topics ------------------------------------------------------------------

test_that("topics names are returned as stored (UPPERCASE, not re-normalized)", {
  with_research_con("full", function(con) {
    out <- dplyr::collect(entropia_topics(con))
    expect_setequal(out$name, c("HUELGA", "SINDICATO"))
    expect_true(all(out$name == toupper(out$name)))
  })
})

test_that("item_topics links items to topics and rows are unique per pair", {
  with_research_con("full", function(con) {
    it <- dplyr::collect(entropia_item_topics(con))
    expect_equal(nrow(it), 2L)
    expect_false(any(duplicated(it[c("item_id", "topic_id")])))
    topics <- dplyr::collect(entropia_topics(con))
    expect_true(all(it$topic_id %in% topics$id))
  })
})

# --- notes: nullable asset_id -------------------------------------------------

test_that("notes expose both item-level (NA) and asset-scoped asset_id", {
  with_research_con("full", function(con) {
    out <- dplyr::collect(entropia_notes(con))
    expect_equal(nrow(out), 2L)
    expect_true(any(is.na(out$asset_id))) # item-level note
    expect_true(any(!is.na(out$asset_id))) # asset-scoped note
    # The asset-scoped note resolves to an existing asset.
    assets <- dplyr::collect(entropia_assets(con))
    expect_true(all(out$asset_id[!is.na(out$asset_id)] %in% assets$id))
  })
})

# --- annotations ---------------------------------------------------------------

test_that("annotations surface kind/page and coordinates", {
  with_research_con("full", function(con) {
    out <- dplyr::collect(entropia_annotations(con))
    expect_equal(nrow(out), 1L)
    expect_identical(out$kind, "rectangle")
    expect_identical(out$page, 1L)
    expect_type(out$x, "double")
    expect_true(all(c("color", "width", "height") %in% names(out)))
  })
})

# --- datetime_auto on entities/triples (milliseconds in the full fixture) -----

test_that("entropia_collect turns entities/triples created_at into POSIXct", {
  with_research_con("full", function(con) {
    ent <- entropia_collect(entropia_entities(con))
    expect_s3_class(ent$created_at, "POSIXct")
    trp <- entropia_collect(entropia_triples(con))
    expect_s3_class(trp$created_at, "POSIXct")
  })
})

test_that("entities/triples seconds timestamps are guarded on legacy-seconds", {
  with_research_con("legacy-seconds", function(con) {
    ent <- entropia_collect(entropia_entities(con))
    expect_s3_class(ent$created_at, "POSIXct")
    trp <- entropia_collect(entropia_triples(con))
    expect_s3_class(trp$created_at, "POSIXct")
  })
})

# --- legacy / error paths ------------------------------------------------------

test_that("research accessors raise table_missing on schemas without them", {
  with_research_con("mini", function(con) {
    expect_error(entropia_entities(con), class = "entropia_error_table_missing")
    expect_error(entropia_triples(con), class = "entropia_error_table_missing")
    expect_error(entropia_topics(con), class = "entropia_error_table_missing")
    expect_error(entropia_item_topics(con), class = "entropia_error_table_missing")
    expect_error(entropia_annotations(con), class = "entropia_error_table_missing")
  })
})

test_that("notes work on the mini schema (item-level, asset_id NA)", {
  with_research_con("mini", function(con) {
    notes <- entropia_notes(con)
    expect_s3_class(notes, "tbl_sql")
    out <- dplyr::collect(notes)
    expect_equal(nrow(out), 1L)
    expect_true(is.na(out$asset_id)) # item-level note
  })
})

test_that("research accessors reject a closed connection", {
  con <- withr::with_options(
    list(entropiaR.schema_policy = "allow"),
    entropia_connect(ent_fixture("full"))
  )
  entropia_disconnect(con)
  expect_error(entropia_entities(con), class = "entropia_error_invalid_connection")
  expect_error(entropia_triples(con), class = "entropia_error_invalid_connection")
  expect_error(entropia_topics(con), class = "entropia_error_invalid_connection")
  expect_error(entropia_notes(con), class = "entropia_error_invalid_connection")
  expect_error(entropia_annotations(con), class = "entropia_error_invalid_connection")
})
