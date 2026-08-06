# Debug: run the full suite excluding write/export to see if the
# "call dbDisconnect()" warning originates outside my new tests.
pkgload::load_all()
files <- list.files("tests/testthat", pattern = "^test-.*\\.R$")
exclude <- c("test-write.R", "test-export.R")
keep <- setdiff(files, exclude)
cat("Files run (excluding write/export):\n")
cat(paste(keep, collapse = "\n"), "\n\n")
testthat::test_local(filter = paste(tools::file_path_sans_ext(keep), collapse = "|"),
                     reporter = "summary")
invisible(gc())
cat("\nDONE\n")
