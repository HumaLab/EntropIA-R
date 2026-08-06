pkgload::load_all("G:/EntropIA-Stack/EntropIA-R", quiet = TRUE)
# Simulate being inside a test: set testthat context
res <- testthat::test_file("G:/EntropIA-Stack/EntropIA-R/scratch/echo_path_test.R", reporter = "silent", stop_on_failure = FALSE)
cat("test_file exit ok\n")
