library(testthat)
library(devtools)
devtools::load_all("G:/EntropIA-Stack/EntropIA-R", quiet = TRUE)
res <- testthat::test_file(
  "G:/EntropIA-Stack/EntropIA-R/tests/testthat/test-relations.R",
  reporter = "silent"
)
cat("test-relations failures:", sum(res$failed), "\n")
cat("DONE\n")
