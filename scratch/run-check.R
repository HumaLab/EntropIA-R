res <- devtools::check(".", quiet = FALSE)
cat("CHECK STATUS:", res$status, "\n")
df <- res$check_results
if (any(df$errors > 0) || any(df$warnings > 0)) {
  print(df[df$errors > 0 | df$warnings > 0, c("check", "errors", "warnings", "notes")])
  quit(status = 1)
}
cat("NOTES:\n")
print(df[df$notes > 0, c("check", "notes")])
cat("CHECK DONE\n")
