library(lintr)
files <- c(
  "G:/EntropIA-Stack/EntropIA-R/R/analysis.R",
  "G:/EntropIA-Stack/EntropIA-R/R/export.R",
  "G:/EntropIA-Stack/EntropIA-R/tests/testthat/test-dataset.R"
)
for (f in files) {
  lints <- lintr::lint(f)
  types <- table(vapply(lints, function(l) l$linter, character(1)))
  cat("FILE:", basename(f), "| total", length(lints), "\n")
  print(types)
}
cat("LINT SUMMARY DONE\n")
