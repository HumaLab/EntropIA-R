txt <- paste(readLines("man/entropia_connect.Rd", warn = FALSE), collapse = "\n")
cat("has literal \\examples{ via fixed:", grepl("\\examples{", txt, fixed = TRUE), "\n")
cat("has 'examples{' substring:", grepl("examples{", txt, fixed = TRUE), "\n")
cat("regex 'examples\\\\{':", grepl("examples\\{", txt), "\n")

# What does my original pattern actually compile to?
pat <- "\\examples\\{"
cat("pattern as string:", pat, "\n")
cat("pattern bytes:", paste0(charToRaw(pat), collapse = " "), "\n")
cat("grepl(pat):", grepl(pat, txt), "\n")
