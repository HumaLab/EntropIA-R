suppressPackageStartupMessages({
  library(devtools)
  library(lintr)
  library(styler)
})
load_all("G:/EntropIA-Stack/EntropIA-R", quiet = TRUE)

cat("=== LINT (package installed, mirroring CI) ===\n")
lints <- lintr::lint_package(path = "G:/EntropIA-Stack/EntropIA-R")
cat("Lint findings:", length(lints), "\n")
if (length(lints) > 0) print(lints)

cat("\n=== STYLER (should be 0 files changed) ===\n")
res <- styler::style_pkg(
  pkg = "G:/EntropIA-Stack/EntropIA-R",
  strict = TRUE,
  dry = "fail" # errors if any file would change
)
cat("styler dry-run: no files would change (OK)\n")
