# Mirror CI: install the local package into a temp library, then run the gates.
tmplib <- file.path(tempdir(), "gatelib")
dir.create(tmplib, recursive = TRUE, showWarnings = FALSE)
.libPaths(c(tmplib, .libPaths()))
ok <- system2(
  file.path(R.home("bin"), "R"),
  c("CMD", "INSTALL", "--no-multiarch", "--with-keep.source",
    "--library", shQuote(tmplib), shQuote(".")),
  stdout = TRUE, stderr = TRUE
)
cat("install tail:", paste(tail(ok, 2), collapse = " | "), "\n")

cat("\n=== LINT (installed, LINTR_ERROR_ON_LINT) ===\n")
res <- lintr::lint_package()
cat("lint count:", length(res), "\n")
if (length(res)) print(res)
stopifnot(length(res) == 0L)
cat("lint OK\n")

cat("\n=== STYLER (dry) ===\n")
sr <- styler::style_pkg(strict = TRUE, dry = "on")
if (is.data.frame(sr)) {
  changed <- sr[[ncol(sr)]]
  cat("files styler would change:", sum(changed), "\n")
  if (sum(changed) > 0) print(sr[changed, 1])
  stopifnot(!any(changed))
}
cat("styler OK\n")

cat("\n=== SPELLING ===\n")
sp <- spelling::spell_check_package(vignettes = TRUE)
if (nrow(sp) > 0) { print(sp); stop("spelling errors") }
cat("spelling OK\n")
