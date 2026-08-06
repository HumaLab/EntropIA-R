library(testthat)
library(devtools)
devtools::load_all("G:/EntropIA-Stack/EntropIA-R", quiet = TRUE)
res <- testthat::test_dir(
  "G:/EntropIA-Stack/EntropIA-R/tests/testthat",
  reporter = "silent",
  stop_on_failure = FALSE
)
for (r in res) {
  for (e in r$results) {
    if (inherits(e, "expectation_skip")) {
      cat("SKIP in file:", r$file, "| test:", r$test, "| msg:", e$message, "\n")
    }
  }
}
cat("SKIP SEARCH DONE\n")
