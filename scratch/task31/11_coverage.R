# Task 31 audit 4: coverage on the four core modules
suppressMessages({ devtools::load_all(".", quiet = TRUE) })
library(covr)

cov <- package_coverage(line_exclusions = NULL, quiet = TRUE, type = "tests")
res <- as.data.frame(cov)

core <- c("R/connect.R", "R/schema.R", "R/corpus.R", "R/collect.R")
cat("=== core module coverage ===\n")
ok <- TRUE
for (f in core) {
  sub <- res[res$filename == f, ]
  total <- nrow(sub)
  covered <- sum(sub$value > 0)
  pct <- if (total > 0) round(100 * covered / total, 1) else NA
  cat(sprintf("%-16s %6.1f%%  (%d/%d expressions)\n", f, pct, covered, total))
  if (is.na(pct) || pct < 80) ok <- FALSE
}

# package-level total for reference
pkg_total <- nrow(res)
pkg_covered <- sum(res$covered > 0)
cat(sprintf("%-16s %6.1f%%  (%d/%d expressions)\n", "PACKAGE TOTAL",
            round(100 * pkg_covered / pkg_total, 1), pkg_covered, pkg_total))

if (!ok) {
  cat("\nCOVERAGE GATE: FAIL (a core module is below 80%)\n")
  quit(status = 1)
}
cat("\nCOVERAGE GATE: PASS\n")
