library(yaml)
files <- list.files(".github/workflows", pattern = "[.]ya?ml$", full.names = TRUE)
for (f in files) {
  res <- tryCatch(yaml::read_yaml(f), error = function(e) e)
  if (inherits(res, "error")) {
    cat("PARSE FAIL:", f, "->", conditionMessage(res), "\n")
  } else {
    cat("OK:", f, "\n")
  }
}
# Quick structural check of the new/updated workflows
rc <- yaml::read_yaml(".github/workflows/R-CMD-check.yaml")
cat("R-CMD-check matrix size:", length(rc$jobs$`R-CMD-check`$strategy$matrix$config), "\n")
ln <- yaml::read_yaml(".github/workflows/lint.yaml")
cat("lint jobs:", paste(names(ln$jobs), collapse = ", "), "\n")
cv <- yaml::read_yaml(".github/workflows/coverage.yaml")
cat("coverage job:", names(cv$jobs), "\n")
sp <- yaml::read_yaml(".github/workflows/spelling.yaml")
cat("spelling job:", names(sp$jobs), "\n")
