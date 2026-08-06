# Tests for Task 28: lifecycle badges + error/warning message audit.
#
# Covers (1) the experimental lifecycle badge on the analysis layer, (2) the
# deprecation scaffolding documented in the package help, (3) the audit gate:
# no bare stop()/warning() without class+cli anywhere in R/, and (4) the
# malformed-JSON tolerant-read warnings (class + stable messages).

# Read the rendered Rd text for an exported function, or NULL when missing.
# Two sources cover both test contexts:
#   * devtools::test()/load_all -- the source tree man/ (pkgload maps
#     system.file("man", ...) to the package's man/);
#   * R CMD check -- installed packages compile man/ into the help DB, so the
#     raw Rd is unavailable and the rendered help text is read instead.
# Both carry the same roxygen-generated content.
ent_rd_text <- function(fn) {
  rd <- system.file("man", paste0(fn, ".Rd"), package = "entropiaR")
  if (nzchar(rd) && file.exists(rd)) {
    return(paste(readLines(rd, warn = FALSE), collapse = "\n"))
  }
  h <- tryCatch(utils::help(fn, package = "entropiaR"), error = function(e) NULL)
  if (is.null(h) || length(h) == 0L) return(NULL)
  rdobj <- tryCatch(utils:::.getHelpFile(h), error = function(e) NULL)
  if (is.null(rdobj)) return(NULL)
  paste(capture.output(tools::Rd2txt(rdobj)), collapse = "\n")
}

# The source R/ directory for the grep gate. Only available when running from
# the source tree (load_all); the installed package ships no .R source, so the
# gate skips there (the CI grep job covers check).
ent_r_source_dir <- function() {
  man <- system.file("man", package = "entropiaR")
  if (!nzchar(man)) return(NA_character_)
  dirname(man)
}

# --- lifecycle badges on the analysis layer ----------------------------------

test_that("analysis-layer docs carry the experimental lifecycle badge", {
  experimental <- c(
    "entropia_temporal_profile",
    "entropia_document_lengths",
    "entropia_entity_frequency",
    "entropia_topic_frequency",
    "entropia_compare_collections",
    "entropia_analysis_dataset"
  )
  skip_if(
    is.null(ent_rd_text(experimental[1L])),
    "documentation not readable (source man/ unavailable; R CMD check covers Rd validity)"
  )
  for (fn in experimental) {
    txt <- ent_rd_text(fn)
    expect_false(is.null(txt), info = paste0(fn, " Rd file missing (run devtools::document())"))
    expect_match(
      txt, "[Experimental]", fixed = TRUE,
      info = paste0(fn, " should carry the experimental lifecycle badge")
    )
  }
})

test_that("badges are scoped: entity accessors carry no lifecycle badge", {
  # The experimental stage is declared only for the analysis layer (v1); the
  # stable accessor surface must not show a badge.
  skip_if(
    is.null(ent_rd_text("entropia_items")),
    "documentation not readable (source man/ unavailable; R CMD check covers Rd validity)"
  )
  for (fn in c("entropia_items", "entropia_assets", "entropia_entities", "entropia_search")) {
    txt <- ent_rd_text(fn)
    expect_false(is.null(txt), info = paste0(fn, " Rd file missing"))
    expect_false(
      grepl("[Experimental]", txt, fixed = TRUE),
      info = paste0(fn, " should not carry a lifecycle badge")
    )
  }
})

# --- deprecation scaffolding documented in the package help ------------------

test_that("package help documents the deprecate_warn scaffolding", {
  txt <- ent_rd_text("entropiaR-package")
  skip_if(is.null(txt), "package help not readable (source man/ unavailable)")
  expect_match(txt, "deprecate_warn", fixed = TRUE)
  expect_match(txt, "lifecycle", fixed = TRUE)
  expect_match(txt, "experimental", fixed = TRUE)
})

# --- deprecation scaffolding emits lifecycle warnings ------------------------

test_that("ent_deprecate emits a lifecycle deprecation warning", {
  w <- tryCatch(
    entropiaR:::ent_deprecate("1.0.0", "entropia_old_function()", "entropia_new_function()"),
    warning = function(w) w
  )
  expect_s3_class(w, "lifecycle_warning_deprecated")
  expect_match(conditionMessage(w), "was deprecated", fixed = TRUE)
  expect_match(conditionMessage(w), "entropia_new_function", fixed = TRUE)
})

# --- audit gate: no bare stop()/warning() in R/ ------------------------------

test_that("no bare stop() or warning() without class+cli in R/", {
  r_dir <- ent_r_source_dir()
  skip_if(
    is.na(r_dir) || !dir.exists(file.path(r_dir, "R")),
    "R/ source not available from the installed package (CI grep job covers check)"
  )
  r_files <- list.files(file.path(r_dir, "R"), pattern = "[.]R$", full.names = TRUE)
  skip_if(length(r_files) < 10, "R/ source tree incomplete")
  hits <- character(0)
  for (f in r_files) {
    lines <- readLines(f, warn = FALSE)
    # Strip roxygen and inline comments: only runnable code is audited.
    code <- gsub("#.*$", "", lines)
    idx <- grep("\\bstop\\s*\\(|\\bwarning\\s*\\(", code)
    hits <- c(hits, sprintf("%s:%d: %s", basename(f), idx, trimws(lines[idx])))
  }
  if (length(hits) > 0L) {
    fail(paste0(
      "bare stop()/warning() found in R/ -- every message must be cli-formatted ",
      "with a stable class (use ent_abort/cli::cli_warn/cnd_signal):\n",
      paste(hits, collapse = "\n")
    ))
  }
  expect_length(hits, 0L)
})

# --- malformed-JSON warnings carry class + stable messages -------------------

test_that("malformed JSON warning carries entropia_warn_malformed_json", {
  expect_warning(
    entropiaR:::ent_parse_json_col('{"unclosed": '),
    class = "entropia_warn_malformed_json"
  )
  expect_warning(
    entropiaR:::ent_parse_json_col(c('{"ok": 1}', '{"bad": ')),
    class = "entropia_warn_malformed_json"
  )
})

test_that("collect warns on malformed JSON in a contract column", {
  # A reachable integration path: llm_results.result is a plain TEXT json
  # column with no generated-column json() guard, so a malformed value can
  # actually be stored -- unlike items.metadata, whose STORED generated column
  # (search_text = json(metadata)) makes SQLite reject malformed JSON at write.
  path <- ent_fixture("full")
  wcon <- DBI::dbConnect(RSQLite::SQLite(), path)
  DBI::dbExecute(
    wcon,
    "UPDATE llm_results SET result = '{\"bad\": '
     WHERE id = (SELECT id FROM llm_results LIMIT 1)"
  )
  DBI::dbDisconnect(wcon)
  con <- entropia_connect(path)
  on.exit(entropia_disconnect(con), add = TRUE)
  expect_warning(
    entropia_collect(entropia_llm_results(con)),
    class = "entropia_warn_malformed_json"
  )
})

test_that("entropia_metadata warns on malformed items.metadata (defensive)", {
  # The app's generated search_text column makes SQLite reject malformed
  # items.metadata, so this path cannot arise from a written row on a real DB.
  # It can still be reached on a hand-rolled table without the generated
  # column, and the tolerant read must not fail the collect.
  tmp <- tempfile(fileext = ".sqlite")
  db <- DBI::dbConnect(RSQLite::SQLite(), tmp)
  DBI::dbExecute(
    db,
    "CREATE TABLE _migrations (
       id INTEGER PRIMARY KEY AUTOINCREMENT,
       name TEXT NOT NULL UNIQUE,
       applied_at INTEGER NOT NULL)"
  )
  DBI::dbExecute(
    db,
    "INSERT INTO _migrations (name, applied_at) VALUES ('0029_rag_chunks', 1768478400)"
  )
  DBI::dbExecute(
    db,
    "CREATE TABLE items (
       id            TEXT PRIMARY KEY,
       title         TEXT NOT NULL,
       collection_id TEXT NOT NULL,
       metadata      TEXT,
       created_at    INTEGER NOT NULL,
       updated_at    INTEGER NOT NULL)"
  )
  DBI::dbExecute(
    db,
    "INSERT INTO items (id, title, collection_id, metadata, created_at, updated_at)
     VALUES ('i-1', 'T', 'c-1', '{\"bad\": ', 1768478400000, 1768478400000)"
  )
  DBI::dbDisconnect(db)
  withr::with_options(list(entropiaR.schema_policy = "allow"), {
    con <- entropia_connect(tmp)
    on.exit(entropia_disconnect(con), add = TRUE)
    expect_warning(entropia_metadata(con), class = "entropia_warn_malformed_json")
  })
})

test_that("key messages have stable snapshots", {
  # malformed JSON (collect path)
  w <- tryCatch(
    entropiaR:::ent_parse_json_col('{"unclosed": '),
    warning = function(w) w
  )
  expect_snapshot(conditionMessage(w))

  # malformed items.metadata (domain path)
  tmp <- tempfile(fileext = ".sqlite")
  db <- DBI::dbConnect(RSQLite::SQLite(), tmp)
  DBI::dbExecute(
    db,
    "CREATE TABLE _migrations (
       id INTEGER PRIMARY KEY AUTOINCREMENT,
       name TEXT NOT NULL UNIQUE,
       applied_at INTEGER NOT NULL)"
  )
  DBI::dbExecute(
    db,
    "INSERT INTO _migrations (name, applied_at) VALUES ('0029_rag_chunks', 1768478400)"
  )
  DBI::dbExecute(
    db,
    "CREATE TABLE items (
       id            TEXT PRIMARY KEY,
       title         TEXT NOT NULL,
       collection_id TEXT NOT NULL,
       metadata      TEXT,
       created_at    INTEGER NOT NULL,
       updated_at    INTEGER NOT NULL)"
  )
  DBI::dbExecute(
    db,
    "INSERT INTO items (id, title, collection_id, metadata, created_at, updated_at)
     VALUES ('i-1', 'T', 'c-1', '{\"bad\": ', 1768478400000, 1768478400000)"
  )
  DBI::dbDisconnect(db)
  withr::with_options(list(entropiaR.schema_policy = "allow"), {
    con <- entropia_connect(tmp)
    on.exit(entropia_disconnect(con), add = TRUE)
    w2 <- tryCatch(entropia_metadata(con), warning = function(w) w)
    expect_snapshot(conditionMessage(w2))
  })

  # write stub (v2 contract error)
  example_db <- system.file("extdata", "entropia-example.sqlite", package = "entropiaR")
  con2 <- entropia_connect(example_db)
  on.exit(entropia_disconnect(con2), add = TRUE)
  err <- tryCatch(
    entropia_insert(con2, "items", data.frame(id = "x")),
    error = identity
  )
  expect_s3_class(err, "entropia_error_write_disabled")
  expect_snapshot(conditionMessage(err))
})
