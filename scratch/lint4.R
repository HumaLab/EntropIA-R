pkgload::load_all("G:/EntropIA-Stack/EntropIA-R", quiet = TRUE)
res <- lintr::lint("G:/EntropIA-Stack/EntropIA-R/tests/testthat/test-quality.R")
cat("test-quality.R lints:", length(res), "\n")
if (length(res)) print(res)
