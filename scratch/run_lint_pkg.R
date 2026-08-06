suppressMessages(library(lintr))
l <- lint_package(".")
cat("TOTAL:", length(l), "\n")
if (length(l) > 0) print(l)
