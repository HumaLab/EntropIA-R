Sys.setenv(NOT_CRAN = "true")
pkgload::load_all("G:/EntropIA-Stack/EntropIA-R", quiet = TRUE)
options(testthat.progress.max_fails = 200)
res <- testthat::test_file("G:/EntropIA-Stack/EntropIA-R/tests/testthat/test-lifecycle.R",
                           reporter = "summary", stop_on_failure = FALSE)
df <- as.data.frame(res)
cat("TOTAL:", nrow(df), "PASS:", sum(df$passed), "FAIL:", sum(df$failed), "WARN:", sum(df$warning), "SKIP:", sum(df$skipped), "\n")
bad <- df[df$failed > 0 | df$error > 0, c("test", "failed", "error"), drop = FALSE]
if (nrow(bad) > 0) print(bad)
