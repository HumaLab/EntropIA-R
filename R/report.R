# Frozen reports consume the same overview tables as scripts and the dashboard.

ent_report_redact <- function(x) {
  x$provenance$source_path <- NULL
  x$selection$collection_ids <- NULL
  x$selection$entity_source <- NULL
  x$selection$model_name <- NULL
  if (is.data.frame(x$collections) && nrow(x$collections)) {
    ids <- x$collections$collection_id
    labels <- paste("Colecci\u00f3n", seq_along(ids))
    x$collections$collection_id <- paste0("collection-", seq_along(ids))
    x$collections$collection_name <- labels
    if (is.data.frame(x$quality) && "group_id" %in% names(x$quality)) {
      matched <- match(x$quality$group_id, ids)
      keep <- !is.na(matched)
      x$quality$group_id[keep] <- x$collections$collection_id[matched[keep]]
      x$quality$group[keep] <- labels[matched[keep]]
    }
  }
  if (is.data.frame(x$entities) && "value" %in% names(x$entities)) {
    values <- unique(x$entities$value)
    x$entities$value <- paste("Entidad", match(x$entities$value, values))
  }
  if (is.data.frame(x$topics) && "name" %in% names(x$topics)) {
    x$topics$name <- paste("Tema", match(x$topics$name, unique(x$topics$name)))
  }
  x$provenance$redacted <- TRUE
  x
}

#' Render a frozen, shareable EDA dashboard with Quarto
#'
#' Renders the tables returned by [entropia_overview()] as a standalone HTML
#' dashboard using the bundled Quarto template. It does not query SQLite,
#' recompute metrics, start a Shiny server or include document text. Quarto must
#' be installed separately and available on `PATH`; `ggplot2`, `knitr` and
#' `rmarkdown` are optional rendering dependencies. Existing destination files
#' are never overwritten. Temporary rendering files are removed on exit.
#'
#' By default source paths and collection filters are removed, and collection,
#' entity and topic labels are replaced with report-local labels. Aggregated
#' values can still disclose information: review every report before sharing.
#' The redacted report is a presentation artifact, not a complete replay recipe.
#' Use `redact = FALSE` only for a trusted audience.
#'
#' @param x The complete list returned by [entropia_overview()].
#' @param path Destination HTML file in an existing directory.
#' @param redact Whether to remove paths and replace identifying labels.
#' @return Normalized output path, invisibly, after successful rendering.
#' @export
#' @examples
#' \dontrun{
#' con <- entropia_connect("study-snapshot.sqlite")
#' eda <- entropia_overview(con)
#' entropia_disconnect(con)
#' entropia_report(eda, "study.html")
#' }
entropia_report <- function(x, path, redact = TRUE) {
  required <- c("counts", "collections", "temporal", "quality", "entities", "topics")
  if (!is.list(x) || !all(required %in% names(x)) ||
    !all(vapply(x[required], is.data.frame, logical(1)))) {
    ent_abort("entropia_error_invalid_argument", "{.arg x} must be an entropia overview.")
  }
  if (!is.logical(redact) || length(redact) != 1L || is.na(redact)) {
    ent_abort("entropia_error_invalid_argument", "{.arg redact} must be TRUE or FALSE.")
  }
  path <- ent_validate_export_path(path)
  if (file.exists(path)) {
    ent_abort("entropia_error_dest_exists", "Report destination already exists: {.path {path}}.")
  }
  if (!dir.exists(dirname(path))) {
    ent_abort("entropia_error_not_found", "The report destination directory does not exist.")
  }
  quarto <- Sys.which("quarto")
  if (!nzchar(quarto)) {
    ent_abort("entropia_error_missing_dependency", "Install Quarto and add its executable to PATH.")
  }
  for (pkg in c("ggplot2", "knitr", "rmarkdown")) {
    if (!requireNamespace(pkg, quietly = TRUE)) {
      ent_abort("entropia_error_missing_dependency", "Rendering requires {.pkg {pkg}}.")
    }
  }
  template <- system.file("templates", "overview.qmd", package = "entropiaR")
  if (!nzchar(template)) {
    ent_abort("entropia_error_not_found", "The bundled Quarto template is missing.")
  }
  work <- tempfile("entropia-report-")
  dir.create(work)
  on.exit(unlink(work, recursive = TRUE), add = TRUE)
  input <- file.path(work, "overview.qmd")
  if (!file.copy(template, input)) {
    ent_abort("entropia_error_copy_failed", "Could not prepare the report template.")
  }
  if (redact) x <- ent_report_redact(x)
  saveRDS(x, file.path(work, "overview.rds"))
  work <- normalizePath(work, winslash = "/", mustWork = TRUE)
  input <- normalizePath(input, winslash = "/", mustWork = TRUE)
  result <- system2(
    quarto,
    c("render", shQuote(input), "--output-dir", shQuote(work)),
    stdout = TRUE, stderr = TRUE
  )
  status <- attr(result, "status") %||% 0L
  output <- file.path(work, "overview.html")
  if (status != 0L || !file.exists(output)) {
    ent_abort("entropia_error_unsupported", c(
      "Quarto could not render the report.",
      i = paste(result, collapse = "\n")
    ))
  }
  if (!file.copy(output, path, overwrite = FALSE)) {
    ent_abort("entropia_error_copy_failed", "Could not save the rendered report.")
  }
  invisible(normalizePath(path, winslash = "/", mustWork = TRUE))
}
