suppressMessages(library(lintr))
files <- c("R/corpus.R", "tests/testthat/test-corpus.R")
for (f in files) {
  cat("===", f, "===\n")
  l <- lint(f)
  if (length(l) == 0) cat("  clean\n") else print(l)
}
