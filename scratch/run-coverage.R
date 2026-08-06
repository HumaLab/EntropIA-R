cov <- covr::package_coverage(quiet = TRUE)
res <- covr::coverage_to_list(cov)$filecoverage
core <- c("connect", "schema", "corpus", "collect")
idx <- vapply(names(res), function(n) basename(n) %in% paste0(core, ".R"), logical(1))
core_cov <- res[idx]
core_cov <- core_cov[order(names(core_cov))]
cat("CORE COVERAGE:\n")
print(round(core_cov, 1))
low <- core_cov[core_cov < 80]
if (length(low) > 0) {
  cat("BELOW 80%: ", paste(names(low), round(low, 1), sep = "=", collapse = ", "), "\n")
  quit(status = 1)
}
cat("ALL CORE MODULES >= 80%\n")
