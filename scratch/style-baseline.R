# Check whether the pre-existing codebase is styler-clean.
files <- c("R/connect.R", "R/analysis.R", "R/tables.R",
           "tests/testthat/test-analysis.R", "tests/testthat/test-ai.R")
res <- styler::style_file(files, dry = "on")
for (i in seq_along(res)) {
  el <- res[[i]]
  st <- if (is.list(el)) el$changed else unname(el["changed"])
  cat(basename(files[[i]]), ": ",
      if (identical(st, FALSE) || identical(st, 0L)) "clean" else "CHANGED", "\n",
      sep = "")
}
