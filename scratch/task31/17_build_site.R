suppressMessages({ devtools::load_all(".", quiet = TRUE) })
Sys.setenv(RSTUDIO_PANDOC = "C:/Program Files/RStudio/resources/app/bin/quarto/bin/tools")
r <- tryCatch({
  pkgdown::build_site(".")
  "build ok"
}, error = function(e) paste("ERROR:", substr(conditionMessage(e), 1, 200)))
cat("pkgdown::build_site:", r, "\n")
if (!identical(r, "build ok")) quit(status = 1)
# confirm key pages exist
cat("index.html exists:", file.exists("pkgdown/index.html"), "\n")
cat("reference exists:", file.exists("pkgdown/reference"), "\n")
cat("articles exist:", file.exists("pkgdown/articles"), "\n")
