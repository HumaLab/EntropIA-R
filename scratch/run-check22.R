library(devtools)
chk <- devtools::check("G:/EntropIA-Stack/EntropIA-R", cran = FALSE, manual = FALSE)
# Print the check status
cat("CHECK STATUS:", chk$status, "\n")
for (nm in c("errors", "warnings", "notes")) {
  items <- chk[[nm]]
  cat("==", nm, "==", length(items), "\n")
  if (length(items)) for (i in items) cat(" -", i, "\n")
}
