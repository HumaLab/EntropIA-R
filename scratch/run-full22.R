library(devtools)
devtools::load_all("G:/EntropIA-Stack/EntropIA-R", quiet = TRUE)
res <- devtools::test("G:/EntropIA-Stack/EntropIA-R", reporter = "summary", stop_on_failure = FALSE)
df <- as.data.frame(res)
cat("TOTAL:", sum(df$failed == 0 & df$error == 0), "passed /",
    sum(df$failed) + sum(df$error), "failed /",
    sum(df$warning), "warnings /", sum(df$skipped), "skipped\n")
if (sum(df$failed) > 0 || sum(df$error) > 0) quit(status = 1)
cat("FULL SUITE OK\n")
