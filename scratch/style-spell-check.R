cat("=== STYLER (dry run) ===\n")
res <- styler::style_pkg(strict = TRUE, dry = "on")
print(res)
cat("\n=== SPELLING ===\n")
sp <- spelling::spell_check_package(vignettes = TRUE)
if (nrow(sp) > 0) { print(sp) } else { cat("No spelling errors found.\n") }
