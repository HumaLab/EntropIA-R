# Check whether pkgdown can actually read the current _pkgdown.yml
suppressMessages({ devtools::load_all(".", quiet = TRUE) })

cat("yaml::read_yaml result:\n")
r <- tryCatch({ yaml::read_yaml("_pkgdown.yml"); "parsed ok" },
              error = function(e) paste("ERROR:", conditionMessage(e)))
cat(r, "\n")

cat("\npkgdown::as_pkgdown metadata:\n")
p <- tryCatch({ pkgdown::as_pkgdown(".", override = list()) ; "as_pkgdown ok" },
              error = function(e) paste("ERROR:", substr(conditionMessage(e), 1, 120)))
cat(p, "\n")

# find plain-scalar desc lines containing ': '
lns <- readLines("_pkgdown.yml", warn = FALSE)
cat("\nlines with ': ' inside a value (potential YAML issue):\n")
for (i in seq_along(lns)) {
  if (grepl("^\\s*(desc|contents):", lns[i])) {
    # desc values are plain scalars; flag those containing ': '
    if (grepl("^\\s*desc:", lns[i]) && grepl(": ", lns[i])) cat(sprintf("line %d: %s\n", i, lns[i]))
  }
}
