# Exploratory summaries: only aggregates cross the overview SQL boundary.

ent_eda_arg <- function(message) {
  ent_abort("entropia_error_invalid_argument", message)
}

ent_eda_strings <- function(x, arg) {
  if (!is.null(x) && (!is.character(x) || anyNA(x))) {
    ent_eda_arg("{.arg {arg}} must be NULL or a character vector without missing values.")
  }
  invisible(x)
}

#' Overview of a selected study universe
#'
#' Aggregates the shared study query in SQLite. Raw text, metadata and BLOBs
#' are never materialised. Counts exclude NULL IDs. Collections retain their
#' IDs and may have zero selected items. Temporal counts count study rows,
#' using UTC month starts; missing and invalid dates are recorded in the
#' temporal tibble's `exclusions` attribute. Metadata validity is JSON syntax
#' validity, not a claim about the meaning of metadata.
#'
#' Text eligibility is based on asset type: OCR for image/PDF and
#' transcription for audio/video. Automatic selection prefers a present
#' extraction over transcription, even if that extraction is empty.
#' `empty_text` retains the legacy any-layer definition; `selected_text_empty`
#' and `selected_text_usable` describe the requested source separately.
#' Quality status distinguishes `ok`, `empty`, `invalid`, `no_data` and
#' `not_applicable`. Percentages are fractions, not percentages multiplied by
#' 100. Entity/topic `n` counts occurrences, while `pct` is distinct item
#' prevalence over all selected items. Asset-scoped entities must belong to
#' a selected asset; item-scoped entities need only a selected item.
#'
#' @param con A connection returned by [entropia_connect()].
#' @param collection_ids Collection IDs, NULL for all; an empty vector selects none.
#' @param asset_types Asset types, NULL for all.
#' @param page_assets Include page assets.
#' @param date_var One of item_created_at, item_updated_at, asset_created_at,
#'   collection_created_at or collection_updated_at.
#' @param date_range NULL or an inclusive two-element Date/POSIXct range.
#' @param text_source Text source: auto, extraction or transcription.
#' @param entity_source Optional entity source values. Soft-deleted entities
#'   are excluded unless explicitly selected.
#' @param model_name Optional entity model names.
#' @param min_confidence Optional entity confidence threshold between 0 and 1.
#' @return An ordinary list with counts, collections, asset_types, temporal,
#'   quality, entities, topics, inventory, selection and provenance.
#'   All tabular elements are plain tibbles. Provenance is lightweight origin
#'   metadata, not a snapshot or result digest.
#' @export
entropia_overview <- function(con, collection_ids = NULL, asset_types = NULL,
                              page_assets = TRUE, date_var = "item_created_at",
                              date_range = NULL, text_source = "auto",
                              entity_source = NULL, model_name = NULL,
                              min_confidence = NULL) {
  ent_require_conn(con)
  text_source <- ent_validate_choice(
    text_source, c("auto", "extraction", "transcription"),
    "text_source"
  )
  ent_eda_strings(entity_source, "entity_source")
  ent_eda_strings(model_name, "model_name")
  if (!is.null(min_confidence) && (!is.numeric(min_confidence) ||
    length(min_confidence) != 1L || !is.finite(min_confidence) ||
    min_confidence < 0 || min_confidence > 1)) {
    ent_eda_arg("{.arg min_confidence} must be NULL or one finite number in [0, 1].")
  }
  study <- ent_study_query(con,
    collection_ids = collection_ids,
    asset_types = asset_types, page_assets = page_assets, date_var = date_var,
    date_range = date_range, text = FALSE
  )
  qi <- function(x) as.character(DBI::dbQuoteIdentifier(con, x))
  qs <- function(x) as.character(DBI::dbQuoteString(con, x))
  # The CTE exposes only identifiers, type and the requested timestamp.
  cols <- unique(c("item_id", "asset_id", "collection_id", "asset_type", date_var))
  query <- as.character(dbplyr::sql_render(dplyr::select(study, dplyr::all_of(cols))))
  prefix <- paste0(
    "WITH s AS (", query, "), ",
    "si AS (SELECT DISTINCT item_id, collection_id FROM s ",
    "WHERE item_id IS NOT NULL), ",
    "sa AS (SELECT DISTINCT asset_id, item_id, collection_id, asset_type ",
    "FROM s WHERE asset_id IS NOT NULL) "
  )
  get <- function(sql) tibble::as_tibble(DBI::dbGetQuery(con, paste0(prefix, sql)))
  has <- function(tab, cols) {
    DBI::dbExistsTable(con, tab) && all(cols %in% DBI::dbListFields(con, tab))
  }
  in_sql <- function(col, values) {
    if (!length(values)) {
      return("0")
    }
    paste0(col, " IN (", paste(qs(values), collapse = ","), ")")
  }
  collection_where <- if (is.null(collection_ids)) "1" else in_sql("c.id", collection_ids)
  collections <- get(paste0(
    "SELECT c.id AS collection_id, c.name AS collection_name, ",
    "COALESCE(z.n_items,0) AS n_items, COALESCE(z.n_assets,0) AS n_assets, ",
    "COALESCE(z.n,0) AS n FROM collections c LEFT JOIN (",
    "SELECT collection_id, COUNT(DISTINCT item_id) AS n_items, ",
    "COUNT(DISTINCT asset_id) AS n_assets, COUNT(*) AS n FROM s ",
    "GROUP BY collection_id) z ON c.id=z.collection_id WHERE ",
    collection_where, " ORDER BY c.id"
  ))
  page_expr <- if (has("assets", "parent_asset_id")) {
    paste0(
      "(SELECT COUNT(*) FROM sa JOIN assets a ON a.id=sa.asset_id ",
      "WHERE a.parent_asset_id IS NOT NULL)"
    )
  } else {
    "0"
  }
  counts <- get(paste0(
    "SELECT 'items' AS metric, 'item' AS unit, COUNT(*) AS n FROM si ",
    "UNION ALL SELECT 'assets','asset',COUNT(*) FROM sa ",
    "UNION ALL SELECT 'collections','collection',",
    "COUNT(DISTINCT collection_id) FROM si ",
    "UNION ALL SELECT 'items_without_assets','item',COUNT(*) FROM si ",
    "WHERE NOT EXISTS (SELECT 1 FROM sa WHERE sa.item_id=si.item_id) ",
    "UNION ALL SELECT 'pages','asset',", page_expr
  ))
  counts$n[counts$metric == "collections"] <- nrow(collections)
  types <- get("SELECT asset_type,COUNT(*) AS n FROM sa GROUP BY asset_type ORDER BY asset_type")
  stamp <- qi(date_var)
  # Never format milliseconds with integer printf: SQLite converts to UTC.
  bucket <- paste0(
    "CASE WHEN typeof(", stamp, ") IN ('integer','real') THEN datetime(", stamp,
    "/1000.0,'unixepoch','start of month') END"
  )
  temporal <- get(paste0(
    "SELECT ", bucket, " AS date,COUNT(*) AS n FROM s GROUP BY ", bucket,
    " ORDER BY date"
  ))
  exclusions <- get(paste0(
    "SELECT COALESCE(SUM(", stamp, " IS NULL),0) AS missing, COALESCE(SUM(",
    stamp, " IS NOT NULL AND (", bucket, ") IS NULL),0) AS invalid FROM s"
  ))
  temporal <- temporal[!is.na(temporal$date), , drop = FALSE]
  temporal$date <- as.POSIXct(temporal$date, format = "%Y-%m-%d %H:%M:%S", tz = "UTC")
  attr(temporal, "exclusions") <- exclusions
  quality <- ent_eda_quality(con, get, has, text_source, collections)
  total <- counts$n[counts$metric == "items"]
  entities <- tibble::tibble(
    entity_type = character(), value = character(), n = integer(),
    n_items = integer(), total = numeric(), pct = numeric()
  )
  if (has("entities", c("item_id", "entity_type", "value"))) {
    conditions <- "EXISTS (SELECT 1 FROM si WHERE si.item_id=e.item_id)"
    if (has("entities", "asset_id")) {
      conditions <- paste0(
        conditions,
        " AND (e.asset_id IS NULL OR EXISTS (SELECT 1 FROM sa ",
        "WHERE sa.asset_id=e.asset_id AND sa.item_id=e.item_id))"
      )
    }
    filters <- list(source = entity_source, model_name = model_name)
    for (nm in names(filters)) {
      val <- filters[[nm]]
      if (!is.null(val)) {
        if (!has("entities", nm)) {
          ent_eda_arg(paste(
            "The entities table lacks the requested filter column",
            "{.val {nm}}."
          ))
        }
        conditions <- paste(conditions, "AND", in_sql(paste0("e.", qi(nm)), val))
      }
    }
    if (is.null(entity_source) && has("entities", "source")) {
      conditions <- paste0(
        conditions, " AND (e.source IS NULL OR e.source <> 'manual_deleted')"
      )
    }
    if (!is.null(min_confidence)) {
      if (!has("entities", "confidence")) {
        ent_eda_arg("The entities table lacks confidence; pass min_confidence = NULL.")
      }
      conditions <- paste0(
        conditions, " AND e.confidence >= ",
        as.character(DBI::dbQuoteLiteral(con, min_confidence))
      )
    }
    entities <- get(paste0(
      "SELECT e.entity_type,e.value,COUNT(*) AS n,",
      "COUNT(DISTINCT e.item_id) AS n_items FROM entities e WHERE ",
      conditions,
      " GROUP BY e.entity_type,e.value ORDER BY e.entity_type,n DESC,e.value"
    ))
    entities$total <- rep(total, nrow(entities))
    entities$pct <- if (total == 0) {
      rep(NA_real_, nrow(entities))
    } else {
      entities$n_items / total
    }
  }
  topics <- tibble::tibble(
    name = character(), n = integer(), n_items = integer(),
    total = numeric(), pct = numeric()
  )
  if (has("topics", c("id", "name")) && has("item_topics", c("item_id", "topic_id"))) {
    topics <- get(paste0(
      "SELECT t.name,COUNT(*) AS n,COUNT(DISTINCT it.item_id) AS n_items ",
      "FROM item_topics it JOIN topics t ON t.id=it.topic_id ",
      "WHERE EXISTS (SELECT 1 FROM si WHERE si.item_id=it.item_id) ",
      "GROUP BY t.name ORDER BY n DESC,t.name"
    ))
    topics$total <- rep(total, nrow(topics))
    topics$pct <- if (total == 0) rep(NA_real_, nrow(topics)) else topics$n_items / total
  }
  inventory <- entropia_schema_info(con)
  selection <- list(
    collection_ids = collection_ids, asset_types = asset_types,
    page_assets = page_assets, date_var = date_var, date_range = date_range,
    text_source = text_source, entity_source = entity_source,
    model_name = model_name, min_confidence = min_confidence
  )
  provenance <- list(
    schema_version = ent_attr(con, "schema_version"),
    schema_hash = ent_attr(con, "schema_hash"), source_path = ent_attr(con, "path"),
    package_version = as.character(utils::packageVersion("entropiaR")),
    built_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3Z", tz = "UTC")
  )
  list(
    counts = counts, collections = collections, asset_types = types,
    temporal = temporal, quality = quality, entities = entities, topics = topics,
    inventory = inventory, selection = selection, provenance = provenance
  )
}

# Shared selected-universe quality implementation. get() includes s/si/sa CTEs.
ent_eda_quality <- function(con, get, has, text_source, collections) {
  box <- new.env(parent = emptyenv())
  box$out <- tibble::tibble(
    metric = character(), group_id = character(), group = character(),
    unit = character(), n = numeric(), total = numeric(), pct = numeric(),
    status = character()
  )
  add <- function(metric, x, unit, status = NULL) {
    if (!nrow(x)) {
      return(invisible(NULL))
    }
    if (is.null(status)) status <- ifelse(x$total == 0, "no_data", "ok")
    box$out <- dplyr::bind_rows(box$out, tibble::tibble(
      metric = metric,
      group_id = as.character(x$group_id), group = as.character(x$group),
      unit = unit, n = as.numeric(x$n), total = as.numeric(x$total),
      pct = ifelse(x$total == 0, NA_real_, x$n / x$total), status = status
    ))
  }
  meta_available <- has("items", "metadata")
  meta <- if (meta_available) "i.metadata" else "NULL"
  present <- paste0(
    "(", meta, " IS NOT NULL AND trim(", meta,
    ", char(9)||char(10)||char(13)||' ') <> '')"
  )
  mq <- get(paste0(
    "SELECT si.collection_id AS group_id, COUNT(*) AS total, SUM(",
    present, ") AS n, SUM(CASE WHEN ", present, " THEN json_valid(",
    meta, ") ELSE 0 END) AS valid FROM si JOIN items i ON i.id=si.item_id ",
    "GROUP BY si.collection_id"
  ))
  m <- dplyr::left_join(
    dplyr::transmute(
      collections,
      group_id = as.character(.data$collection_id),
      group = .data$collection_name
    ),
    dplyr::mutate(mq, group_id = as.character(.data$group_id)),
    by = "group_id"
  )
  for (nm in c("total", "n", "valid")) m[[nm]][is.na(m[[nm]])] <- 0
  add(
    "metadata_coverage", m, "item",
    if (!meta_available) {
      rep("not_applicable", nrow(m))
    } else {
      ifelse(m$total == 0, "no_data", ifelse(m$n == 0, "empty", "ok"))
    }
  )
  valid <- m
  valid$total <- m$n
  valid$n <- m$valid
  add(
    "metadata_validity", valid, "item",
    if (!meta_available) {
      rep("not_applicable", nrow(m))
    } else {
      ifelse(
        m$total == 0, "no_data",
        ifelse(m$n == 0, "empty", ifelse(m$valid < m$n, "invalid", "ok"))
      )
    }
  )
  ep <- has("extractions", c("asset_id", "text_content"))
  tp <- has("transcriptions", c("asset_id", "text_content"))
  layer <- function(tab, flag, useful, available) {
    if (!available) {
      return(paste0(
        "SELECT NULL AS asset_id,0 AS ", flag, ",0 AS ", useful, " WHERE 0"
      ))
    }
    paste0(
      "SELECT asset_id,1 AS ", flag, ",",
      "MAX(CASE WHEN text_content IS NOT NULL AND ",
      "trim(text_content,char(9)||char(10)||char(13)||' ') <> '' ",
      "THEN 1 ELSE 0 END) AS ", useful, " FROM ", tab, " GROUP BY asset_id"
    )
  }
  base <- paste0(
    "SELECT sa.*,COALESCE(e.ep,0) AS ep,COALESCE(e.eu,0) AS eu,",
    "COALESCE(t.tp,0) AS tp,COALESCE(t.tu,0) AS tu FROM sa LEFT JOIN (",
    layer("extractions", "ep", "eu", ep),
    ") e ON e.asset_id=sa.asset_id LEFT JOIN (",
    layer("transcriptions", "tp", "tu", tp),
    ") t ON t.asset_id=sa.asset_id"
  )
  selected_present <- switch(text_source,
    auto = "(ep OR tp)",
    extraction = "ep",
    transcription = "tp"
  )
  selected_useful <- switch(text_source,
    auto = "CASE WHEN ep=1 THEN eu ELSE tu END",
    extraction = "eu",
    transcription = "tu"
  )
  eligible <- switch(text_source,
    auto = "asset_type IN ('pdf','image','audio','video')",
    extraction = "asset_type IN ('pdf','image')",
    transcription = "asset_type IN ('audio','video')"
  )
  aggregate <- function(n, total = "1") {
    get(paste0(
      "SELECT asset_type AS group_id,asset_type AS \"group\",",
      "COALESCE(SUM(", n, "),0) AS n,COALESCE(SUM(", total,
      "),0) AS total FROM (", base, ") b GROUP BY asset_type ",
      "ORDER BY asset_type"
    ))
  }
  add(
    "ocr_coverage", aggregate("eu"), "asset",
    if (!ep) rep("not_applicable", nrow(aggregate("eu"))) else NULL
  )
  add(
    "transcription_presence", aggregate("tp"), "asset",
    if (!tp) rep("not_applicable", nrow(aggregate("tp"))) else NULL
  )
  add("empty_text", aggregate("(ep OR tp) AND NOT (eu OR tu)", "(ep OR tp)"), "asset")
  add("any_layer_usable", aggregate("(eu OR tu)"), "asset")
  add("text_eligibility", aggregate(eligible), "asset")
  usable <- aggregate(paste0("(", eligible, ") AND (", selected_useful, ")"), eligible)
  available <- switch(text_source,
    auto = ep || tp,
    extraction = ep,
    transcription = tp
  )
  status <- if (!available) {
    rep("not_applicable", nrow(usable))
  } else {
    ifelse(usable$total == 0, "not_applicable", ifelse(usable$n == 0, "empty", "ok"))
  }
  add("selected_text_usable", usable, "asset", status)
  empty <- aggregate(
    paste0(
      "(", eligible, ") AND ", selected_present, " AND NOT (",
      selected_useful, ")"
    ),
    paste0("(", eligible, ") AND ", selected_present)
  )
  add(
    "selected_text_empty", empty, "asset",
    ifelse(
      !available | usable$total == 0, "not_applicable",
      ifelse(empty$total == 0, "no_data", ifelse(empty$n > 0, "empty", "ok"))
    )
  )
  dplyr::arrange(box$out, .data$metric, .data$group_id)
}

#' Profile collected observations
#'
#' Computes grouped missingness, numeric summaries and categorical frequencies
#' without database access. Numeric statistics use finite values only; missing
#' and non-finite values remain visible in missingness status. Dates are
#' described by class and range, never treated as numeric measurements.
#' Categorical frequencies include an NA category. List columns are described
#' structurally and checked for missingness, but are not stringified into
#' categories. Duplicate rows are exact duplicates over selected columns;
#' duplicate keys use selected columns named id or ending in _id. `n` counts
#' surplus rows, `n_groups` counts repeated identities, and `n_rows` counts
#' all rows participating in duplicates. No fuzzy matching is performed.
#'
#' @param x A collected data frame or tibble.
#' @param columns Columns to profile (tidyselect); NULL selects all.
#' @param by Optional grouping columns (tidyselect).
#' @param sample_n Optional nonnegative integer sample size. Sampling is local,
#'   without replacement, and preserves the caller's RNG state.
#' @param seed Integer seed used only when sample_n is supplied.
#' @return An ordinary list with structure, missing, numeric, categorical,
#'   duplicates and sampling. Tabular components are plain tibbles. Sampling
#'   records original/sample row counts, seed and selected row positions.
#' @export
entropia_profile <- function(x, columns = NULL, by = NULL, sample_n = NULL, seed = 1L) {
  x <- tibble::as_tibble(ent_require_tibble(x))
  cq <- rlang::enquo(columns)
  cols <- if (rlang::quo_is_null(cq)) names(x) else ent_select_cols(x, cq, "columns")
  groups <- ent_select_cols(x, rlang::enquo(by), "by")
  reserved <- c(
    "variable", "statistic", "value", "n", "total", "pct", "status", "rule",
    "n_groups", "n_rows"
  )
  if (length(intersect(groups, reserved))) {
    ent_eda_arg(paste(
      "Rename grouping columns that conflict with profile result columns:",
      "{.val {intersect(groups, reserved)}}."
    ))
  }
  valid_integer <- function(z) {
    is.numeric(z) && length(z) == 1L && is.finite(z) &&
      z == floor(z) && abs(z) <= .Machine$integer.max
  }
  if (!is.null(sample_n) && (!valid_integer(sample_n) || sample_n < 0)) {
    ent_eda_arg("{.arg sample_n} must be NULL or a nonnegative integer.")
  }
  if (!valid_integer(seed)) ent_eda_arg("{.arg seed} must be a finite integer.")
  original_n <- nrow(x)
  indices <- seq_len(original_n)
  if (!is.null(sample_n)) {
    rng <- paste0(".", "Random.seed")
    existed <- exists(rng, envir = .GlobalEnv, inherits = FALSE)
    saved <- if (existed) {
      get(rng, envir = .GlobalEnv, inherits = FALSE)
    } else {
      NULL
    }
    on.exit(
      {
        if (existed) {
          assign(rng, saved, envir = .GlobalEnv)
        } else if (exists(rng, envir = .GlobalEnv, inherits = FALSE)) {
          rm(list = rng, envir = .GlobalEnv)
        }
      },
      add = TRUE
    )
    set.seed(as.integer(seed))
    indices <- sort(sample.int(original_n, min(sample_n, original_n), replace = FALSE))
    x <- x[indices, , drop = FALSE]
  }
  missing_value <- function(z) {
    if (is.list(z)) {
      vapply(
        z,
        function(v) is.null(v) || (length(v) == 1L && is.atomic(v) && is.na(v)),
        logical(1)
      )
    } else {
      is.na(z)
    }
  }
  structure <- dplyr::bind_rows(lapply(cols, function(nm) {
    z <- x[[nm]]
    is_date <- inherits(z, "Date") || inherits(z, "POSIXt")
    good <- if (is_date) !is.na(z) & is.finite(as.numeric(z)) else rep(FALSE, length(z))
    tibble::tibble(
      variable = nm, class = paste(class(z), collapse = "/"),
      type = typeof(z), n = length(z), n_missing = sum(missing_value(z)),
      min = if (any(good)) as.character(min(z[good])) else NA_character_,
      max = if (any(good)) as.character(max(z[good])) else NA_character_,
      contract = if (is_date) "datetime" else if (is.list(z)) "list" else "raw"
    )
  }))
  if (!length(cols)) {
    structure <- tibble::tibble(
      variable = character(), class = character(), type = character(),
      n = integer(), n_missing = integer(), min = character(),
      max = character(), contract = character()
    )
  }
  group_template <- x[0, groups, drop = FALSE]
  missing <- dplyr::bind_cols(group_template, tibble::tibble(
    variable = character(), n = integer(),
    total = integer(), pct = numeric(), status = character()
  ))
  numeric <- dplyr::bind_cols(group_template, tibble::tibble(
    variable = character(),
    statistic = character(), value = numeric()
  ))
  categorical <- dplyr::bind_cols(group_template, tibble::tibble(
    variable = character(),
    value = character(), n = integer(), total = integer(), pct = numeric()
  ))
  duplicates <- dplyr::bind_cols(group_template, tibble::tibble(
    rule = character(), n = integer(),
    n_groups = integer(), n_rows = integer(), total = integer()
  ))
  if (length(groups)) {
    gx <- dplyr::group_by(x, dplyr::across(dplyr::all_of(groups)))
    keys <- dplyr::group_keys(gx)
    parts <- dplyr::group_rows(gx)
  } else {
    keys <- tibble::new_tibble(list(), nrow = 1L)
    parts <- list(seq_len(nrow(x)))
  }
  variables <- setdiff(cols, groups)
  for (i in seq_along(parts)) {
    part <- x[parts[[i]], , drop = FALSE]
    key <- keys[i, , drop = FALSE]
    attach_key <- function(z) dplyr::bind_cols(key[rep(1L, nrow(z)), , drop = FALSE], z)
    for (nm in variables) {
      z <- part[[nm]]
      miss <- missing_value(z)
      number <- is.numeric(z) && !inherits(z, "Date") && !inherits(z, "POSIXt")
      invalid <- if (number) sum(!is.na(z) & !is.finite(z)) else 0L
      missing <- dplyr::bind_rows(missing, attach_key(tibble::tibble(
        variable = nm,
        n = sum(miss), total = length(z),
        pct = if (length(z)) mean(miss) else NA_real_,
        status = if (!length(z)) {
          "no_data"
        } else if (invalid) {
          "invalid"
        } else if (all(miss)) {
          "empty"
        } else {
          "ok"
        }
      )))
      if (number) {
        v <- z[is.finite(z)]
        q <- if (length(v)) {
          as.numeric(stats::quantile(v, c(0.25, 0.5, 0.75),
            names = FALSE
          ))
        } else {
          rep(NA_real_, 3L)
        }
        spread <- q[3L] - q[1L]
        values <- c(
          length(v), if (length(v)) mean(v) else NA_real_,
          if (length(v) > 1L) stats::sd(v) else NA_real_,
          if (length(v)) min(v) else NA_real_, q[1L], q[2L], q[3L],
          if (length(v)) max(v) else NA_real_, spread,
          if (length(v)) sum(v < q[1L] - 1.5 * spread | v > q[3L] + 1.5 * spread) else 0
        )
        numeric <- dplyr::bind_rows(numeric, attach_key(tibble::tibble(
          variable = nm,
          statistic = c(
            "n", "mean", "sd", "min", "q25", "median", "q75", "max", "IQR",
            "outliers"
          ), value = as.numeric(values)
        )))
      } else if (is.character(z) || is.factor(z) || is.logical(z)) {
        freq <- dplyr::count(tibble::tibble(value = as.character(z)), .data$value, name = "n")
        freq <- dplyr::arrange(freq, dplyr::desc(.data$n), .data$value)
        categorical <- dplyr::bind_rows(categorical, attach_key(tibble::tibble(
          variable = rep(
            nm,
            nrow(freq)
          ), value = freq$value, n = freq$n,
          total = rep(length(z), nrow(freq)), pct = freq$n / length(z)
        )))
      }
    }
    rules <- list(exact_rows = cols, exact_keys = cols[grepl("(^id$|_id$)", cols,
      ignore.case = TRUE
    )])
    for (rule in names(rules)) {
      selected <- rules[[rule]]
      if (rule == "exact_keys" && !length(selected)) next
      d <- part[selected]
      later <- duplicated(d)
      involved <- later | duplicated(d, fromLast = TRUE)
      duplicates <- dplyr::bind_rows(duplicates, attach_key(tibble::tibble(
        rule = rule,
        n = sum(later), n_groups = sum(involved & !later), n_rows = sum(involved),
        total = nrow(part)
      )))
    }
  }
  list(
    structure = structure, missing = missing, numeric = numeric,
    categorical = categorical, duplicates = duplicates,
    sampling = list(
      original_n = original_n, n = nrow(x), sample_n = sample_n,
      sampled = !is.null(sample_n), seed = if (is.null(sample_n)) NULL else as.integer(seed),
      row_indices = indices
    )
  )
}
