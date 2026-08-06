pkgload::load_all("G:/EntropIA-Stack/EntropIA-R", quiet = TRUE)
cat("system.file(pkg):", system.file(package = "entropiaR"), "\n")
cat("R dir exists:", file.exists(file.path(system.file(package = "entropiaR"), "R")), "\n")
cat("man dir exists:", file.exists(file.path(system.file(package = "entropiaR"), "man")), "\n")
