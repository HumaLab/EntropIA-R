# What does an INSTALLED package's man/ look like?
for (p in c("DBI", "dplyr", "entropiaR")) {
  ip <- utils::installed.packages()
  if (!p %in% rownames(ip)) { cat(p, ": not installed\n"); next }
  lib <- ip[p, "LibPath"]
  pkgdir <- file.path(lib, p)
  cat("===", p, "===\n")
  cat("has man dir:", dir.exists(file.path(pkgdir, "man")), "\n")
  if (dir.exists(file.path(pkgdir, "man"))) {
    m <- list.files(file.path(pkgdir, "man"))
    cat("man files (first 5):", paste(head(m, 5), collapse = ", "), "\n")
  }
  cat("has help dir:", dir.exists(file.path(pkgdir, "help")), "\n")
  cat("system.file('man', pkg):", system.file("man", package = p), "\n")
}
