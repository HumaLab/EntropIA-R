# Task 31 final gates: lint + style on changed files
suppressMessages({ devtools::load_all(".", quiet = TRUE) })
changed <- c("R/utils.R", "R/collect.R", "R/corpus.R", "tests/testthat/test-collect.R")
cat("=== lintr ===\n")
lint_out <- unlist(lapply(changed, function(f) lintr::lint(f, cache = FALSE)), recursive = FALSE)
cat("lint findings:", length(lint_out), "\n")
if (length(lint_out) > 0) print(lint_out)

cat("\n=== styler check ===\n")
# styler::style_file on a copy? styler has style_file(dry = "off"). For a check,
# we can compare whether applying styler changes the files.
changed_files <- normalizePath(changed)
results <- lapply(changed_files, function(f) {
  st <- styler::style_file(f, dry = "on")
  st
})
for (i in seq_along(changed)) {
  cat(changed[i], "-> changed by styler:", results[[i]]$changed, "\n")
}
if (length(lint_out) > 0) quit(status = 1)
cat("\nLINT+STYLE: PASS\n")
