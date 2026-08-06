suppressMessages({ devtools::load_all(".", quiet = TRUE) })
library(covr)
cov <- package_coverage(line_exclusions = NULL, quiet = TRUE, type = "tests")
res <- as.data.frame(cov)
cat("columns:", paste(names(res), collapse = ", "), "\n")
cat("head:\n")
print(utils::head(res, 3))
cat("class of value col:", class(res$value), "\n")
cat("sum value>0 for connect.R:",
    sum(res[res$filename == "R/connect.R", "value"] > 0), "of",
    nrow(res[res$filename == "R/connect.R", ]), "\n")
