suppressMessages({ devtools::load_all(".", quiet = TRUE) })
library(covr)
cat("attempting package_coverage with quiet=FALSE...\n")
cov <- tryCatch(
  package_coverage(line_exclusions = NULL, quiet = FALSE, type = "tests"),
  error = function(e) { cat("ERROR:", conditionMessage(e), "\n"); NULL }
)
if (!is.null(cov)) {
  res <- as.data.frame(cov)
  cat("rows:", nrow(res), "\n")
  print(table(res$filename))
}
