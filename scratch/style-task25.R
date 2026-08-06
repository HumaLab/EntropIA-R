# Styler check (verification only) on Task 25 files.
pkgload::load_all()
files <- c("R/write.R", "R/export.R",
           "tests/testthat/test-write.R", "tests/testthat/test-export.R")
out <- styler::style_file(files, dry = "on")
for (i in seq_along(out)) {
  changed <- out[[i]]$changed
  cat(basename(files[[i]]), ": ",
      if (isTRUE(changed)) "NEEDS STYLING" else "clean", "\n", sep = "")
}
