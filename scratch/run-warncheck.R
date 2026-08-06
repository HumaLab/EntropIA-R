library(testthat)
library(devtools)
devtools::load_all("G:/EntropIA-Stack/EntropIA-R", quiet = TRUE)
res <- testthat::test_dir(
  "G:/EntropIA-Stack/EntropIA-R/tests/testthat",
  reporter = "silent",
  stop_on_failure = FALSE
)
cat("WARNCHECK DONE\n")
