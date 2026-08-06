library(testthat)
library(devtools)
devtools::load_all("G:/EntropIA-Stack/EntropIA-R", quiet = TRUE)
res <- testthat::test_dir(
  "G:/EntropIA-Stack/EntropIA-R/tests/testthat",
  reporter = "silent",
  stop_on_failure = FALSE
)
tot <- 0; fail <- 0; err <- 0; warn <- 0; skip <- 0
for (r in res) {
  for (e in r$results) {
    tot <- tot + 1
    if (inherits(e, "expectation_failure")) fail <- fail + 1
    if (inherits(e, "expectation_error")) err <- err + 1
    if (inherits(e, "expectation_warning")) warn <- warn + 1
    if (inherits(e, "expectation_skip")) skip <- skip + 1
  }
}
cat(sprintf("TOTAL %d | failed %d | errors %d | warnings %d | skipped %d\n", tot, fail, err, warn, skip))
if (fail > 0 || err > 0) quit(status = 1)
cat("COUNT OK\n")
