pkgload::load_all("G:/EntropIA-Stack/EntropIA-R", quiet = TRUE)
options(testthat.progress.max_fails = 200)
testthat::test_local("G:/EntropIA-Stack/EntropIA-R", filter = "analysis", reporter = "check", stop_on_failure = FALSE)
