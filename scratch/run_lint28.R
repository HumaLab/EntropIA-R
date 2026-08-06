pkgload::load_all("G:/EntropIA-Stack/EntropIA-R", quiet = TRUE)
files <- c(
  "R/analysis.R", "R/collect.R", "R/corpus.R", "R/connect.R", "R/schema.R",
  "R/utils.R", "R/entropiaR-package.R", "tests/testthat/test-lifecycle.R"
)
total <- 0L
for (f in files) {
  res <- lintr::lint(f)
  cat(sprintf("%-45s lints: %d\n", f, length(res)))
  if (length(res) > 0) print(res)
  total <- total + length(res)
}
cat("TOTAL lints:", total, "\n")
