# Export / interoperability (Task 22 provenance I/O; entropia_export lands in
# Task 24).
#
# Reproducibility sidecar: entropia_analysis_dataset() stamps an
# `entropia_prov` attribute onto every dataset it returns.
# entropia_provenance() reads that stamp back; entropia_write_provenance()
# persists it as a JSON sidecar next to the analysis. The JSON records the
# schema version, source path + content hash, the captured filter expressions,
# the package and R versions, and the build timestamp -- everything needed to
# reconstruct the dataset from the database.

#' Read the provenance stamp of a reproducible dataset
#'
#' Returns the `entropia_prov` attribute attached by
#' [entropia_analysis_dataset()]: a list recording the dataset `name`, the
#' database `schema_version`, the schema `content_hash`, the `source_path`, the
#' captured `filters`, the `package_version`, the `built_at` timestamp and the
#' `r_version`. Aborts with `entropia_error_invalid_argument` when `x` carries
#' no provenance stamp.
#'
#' @param x An object carrying a provenance stamp, e.g. the output of
#'   [entropia_analysis_dataset()].
#' @return A list of class `entropia_provenance`.
#' @export
entropia_provenance <- function(x) {
  prov <- attr(x, "entropia_prov", exact = TRUE)
  if (is.null(prov)) {
    ent_abort(
      "entropia_error_invalid_argument",
      c(
        "{.arg x} carries no provenance stamp.",
        i = paste0(
          "Build a reproducible dataset with {.fn entropia_analysis_dataset} ",
          "to attach provenance, then read it back here."
        )
      )
    )
  }
  class(prov) <- c("entropia_provenance", "list")
  prov
}

#' @export
print.entropia_provenance <- function(x, ...) {
  nm <- if (is.null(x$name)) "<unnamed>" else x$name
  cat("entropiaR dataset provenance\n")
  cat("  name:           ", nm, "\n", sep = "")
  ver <- x$schema_version
  if (length(ver) != 1L || is.na(ver)) ver <- "unknown"
  cat("  schema version: ", ver, "\n", sep = "")
  cat("  content hash:   ", x$content_hash, "\n", sep = "")
  cat("  source path:    ", x$source_path, "\n", sep = "")
  if (length(x$filters) > 0L) {
    cat("  filters:        ", paste(x$filters, collapse = "; "), "\n", sep = "")
  }
  cat("  package:        ", x$package_version, "\n", sep = "")
  cat("  built at:       ", x$built_at, "\n", sep = "")
  cat("  R version:      ", x$r_version, "\n", sep = "")
  invisible(x)
}

#' Write a provenance sidecar (JSON)
#'
#' Persists the provenance stamp of a reproducible dataset as a JSON file, the
#' sidecar that travels with the analysis output. `NULL` values are written as
#' JSON `null` and `NA` values as `null`, so the file round-trips through
#' [jsonlite::fromJSON()] back to the same structure (apart from the list
#' class). The file is UTF-8.
#'
#' @param x An object carrying a provenance stamp (see [entropia_provenance()]).
#' @param path Destination file path. Must be a single path.
#' @return The normalized `path`, invisibly.
#' @export
entropia_write_provenance <- function(x, path) {
  if (!is.character(path) || length(path) != 1L || is.na(path)) {
    ent_abort("entropia_error_invalid_argument", "{.arg path} must be a single path.")
  }
  prov <- entropia_provenance(x)
  json <- jsonlite::toJSON(
    unclass(prov),
    auto_unbox = TRUE,
    pretty = TRUE,
    null = "null",
    na = "null"
  )
  writeLines(json, path, useBytes = TRUE)
  invisible(path)
}
