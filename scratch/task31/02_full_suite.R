# Task 31 audit 3: run the full testthat suite
suppressMessages({
  devtools::load_all(".", quiet = TRUE)
})
library(testthat)

res <- test_dir("tests/testthat", package = "entropiaR", reporter = "summary", stop_on_failure = FALSE)

df <- as.data.frame(res)
cat("\n=== FULL SUITE RESULTS ===\n")
cat("files:", length(unique(df$file)), "\n")
cat("passed:", sum(df$passed), "\n")
cat("failed:", sum(df$failed), "\n")
cat("warnings:", sum(df$warning), "\n")
cat("skipped:", sum(df$skipped), "\n")

if (sum(df$failed) > 0) {
  cat("\nFAILURES:\n")
  print(df[df$failed > 0, c("file", "context", "test", "failed")])
  quit(status = 1)
}
cat("\nFULL SUITE: PASS\n")
