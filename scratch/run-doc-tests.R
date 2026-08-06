cat("=== roxygenise ===\n")
suppressMessages(roxygen2::roxygenise("."))
cat("roxygenise done\n")
cat("=== full test suite ===\n")
res <- testthat::test_local(".", reporter = "summary")
df <- as.data.frame(res)
cat("FAILED:", sum(df$failed), " WARN:", sum(df$warning), " SKIP:", sum(df$skipped), "\n")
if (sum(df$failed) > 0) {
  bad <- df[df$failed > 0, ]
  print(bad[, c("file", "test")])
  quit(status = 1)
}
cat("SUITE GREEN\n")
