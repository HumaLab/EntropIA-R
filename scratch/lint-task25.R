# Lint the files touched by Task 25.
pkgload::load_all()
files <- c("R/write.R", "R/export.R",
           "tests/testthat/test-write.R", "tests/testthat/test-export.R")
for (f in files) {
  cat("=== ", f, " ===\n", sep = "")
  lints <- lintr::lint(f)
  if (length(lints) == 0L) {
    cat("  (clean)\n")
  } else {
    print(lints)
  }
}
