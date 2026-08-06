Sys.setenv(NOT_CRAN = "true")
options(testthat.progress.max_fails = 100)
res <- devtools::test("G:/EntropIA-Stack/EntropIA-R", reporter = "summary",
                      stop_on_failure = FALSE)
df <- as.data.frame(res)
cat("TOTAL_RUNS:", nrow(df), "\n")
cat("PASS:", sum(df$passed), "FAIL:", sum(df$failed), "WARN:", sum(df$warning), "SKIP:", sum(df$skipped), "\n")
bad <- df[df$failed > 0 | df$error > 0, c("file", "test", "failed", "error"), drop = FALSE]
if (nrow(bad) > 0) print(bad)
