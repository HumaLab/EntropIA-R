# Task 31 audit 5: documentation completeness
suppressMessages({ devtools::load_all(".", quiet = TRUE) })

exports <- sort(getNamespaceExports("entropiaR"))
rds <- list.files("man", pattern = "\\.Rd$", full.names = TRUE)
rd_names <- sub("\\.Rd$", "", basename(rds))

# 1. Every export has an Rd file
missing_rd <- setdiff(exports, rd_names)
cat("exports:", length(exports), "| Rd files:", length(rd_names), "\n")
cat("missing Rd:", if (length(missing_rd)) paste(missing_rd, collapse = ",") else "none", "\n")

# 2. Every Rd for an exported fn has an \examples section
no_ex <- character()
for (rd in rds) {
  nm <- sub("\\.Rd$", "", basename(rd))
  if (nm %in% exports) {
    txt <- paste(readLines(rd, warn = FALSE), collapse = "\n")
    if (!grepl("\\examples{", txt, fixed = TRUE)) no_ex <- c(no_ex, nm)
  }
}
cat("Rd without \\examples:", if (length(no_ex)) paste(no_ex, collapse = ",") else "none", "\n")

# 3. README/NEWS present and non-trivial
cat("README lines:", length(readLines("README.md")), "\n")
cat("NEWS lines:", length(readLines("NEWS.md")), "\n")

# 4. pkgdown metadata parses and has reference groups
y <- yaml::read_yaml("_pkgdown.yml")
ref <- y$reference
cat("pkgdown reference groups:", length(ref), "\n")
pd <- tryCatch({ pkgdown::as_pkgdown(".", override = list()); "parse ok" },
               error = function(e) paste("ERROR:", conditionMessage(e)))
cat("pkgdown::as_pkgdown:", pd, "\n")
if (!identical(pd, "parse ok")) quit(status = 1)

# 5. Vignettes listed in pkgdown articles
art <- y$articles
cat("pkgdown articles groups:", length(art), "\n")
if (length(art) < 1) quit(status = 1)

fail <- length(missing_rd) > 0 || length(no_ex) > 0
if (fail) quit(status = 1)
cat("\nDOCS CHECK: PASS\n")
