Sys.setenv(RSTUDIO_PANDOC = "C:/Program Files/RStudio/resources/app/bin/quarto/bin/tools")
library(devtools)
load_all("G:/EntropIA-Stack/EntropIA-R", quiet = TRUE)
res <- devtools::check(
  pkg = "G:/EntropIA-Stack/EntropIA-R",
  document = FALSE,
  manual = FALSE,
  cran = FALSE,
  quiet = FALSE
)
cat("\n=== CHECK RESULT: errors =", res$errors, " warnings =", res$warnings, " notes =", res$notes, "\n")
