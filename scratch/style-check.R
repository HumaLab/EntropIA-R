res <- styler::style_pkg(strict = TRUE, dry = "on")
changed <- res[res[[length(res)]], , drop = FALSE]
cat("Files that WOULD change:", nrow(changed), "\n")
print(changed[, 1])
