Sys.setenv(NOT_CRAN = "true")
Sys.setenv(RSTUDIO_PANDOC = "C:/Program Files/RStudio/resources/app/bin/quarto/bin/tools")
res <- devtools::check("G:/EntropIA-Stack/EntropIA-R", cran = FALSE,
                       args = "--no-manual", error_on = "never",
                       quiet = TRUE)
cat("\n=== CHECK SUMMARY ===\n")
cat("errors:", length(res$errors), "\n")
if (length(res$errors)) print(res$errors)
cat("warnings:", length(res$warnings), "\n")
if (length(res$warnings)) print(res$warnings)
cat("notes:", length(res$notes), "\n")
if (length(res$notes)) print(res$notes)
