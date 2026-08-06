Sys.setenv(RSTUDIO_PANDOC = "C:/Program Files/RStudio/resources/app/bin/quarto/bin/tools")
suppressMessages({ devtools::load_all(".", quiet = TRUE) })
# Run a full check, capturing the status line
res <- devtools::check(".", document = FALSE, manual = FALSE, args = "--no-manual",
                       quiet = TRUE, error_on = "never")
cat("check_dir:", res$checkdir, "\n")
lines <- readLines(file.path(res$checkdir, "00check.log"), warn = FALSE)
status <- grep("^Status:", lines, value = TRUE)
cat("CHECK STATUS:", status, "\n")
# Count errors/warnings/notes lines
err <- grep(" ERROR", lines, value = TRUE)
wrn <- grep(" WARNING", lines, value = TRUE)
nte <- grep(" NOTE", lines, value = TRUE)
cat("ERROR lines:", length(err), "\n")
cat("WARNING lines:", length(wrn), "\n")
cat("NOTE lines:", length(nte), "\n")
cat("--- NOTE details ---\n")
cat(nte, sep = "\n")
if (length(err) > 0 || length(wrn) > 0) {
  cat("--- details ---\n")
  cat(err, sep = "\n"); cat(wrn, sep = "\n")
  quit(status = 1)
}
cat("\nR CMD CHECK: PASS\n")
