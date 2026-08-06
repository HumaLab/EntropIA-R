pkgload::load_all("G:/EntropIA-Stack/EntropIA-R", quiet = TRUE)
for (f in c("R/collect.R", "R/quality.R", "R/corpus.R")) {
  res <- lintr::lint(file.path("G:/EntropIA-Stack/EntropIA-R", f))
  cat(f, "lints:", length(res), "\n")
  if (length(res)) print(res)
}
