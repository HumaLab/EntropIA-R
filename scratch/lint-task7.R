files <- c("R/validate.R", "R/schema.R", "tests/testthat/test-validate.R")
for (f in files) {
  res <- lintr::lint(f)
  cat("==", f, "== total:", length(res), "\n")
  for (x in res) {
    cat("  ", x$line_number, ":", x$column, ": [", x$linter, "] ", x$message, "\n", sep = "")
  }
}
