pkgload::load_all("G:/EntropIA-Stack/EntropIA-R", quiet = TRUE)
w <- tryCatch(
  withCallingHandlers(
    entropiaR:::ent_deprecate("1.0.0", "entropia_old_function()", "entropia_new_function()"),
    warning = function(w) { invokeRestart("muffleWarning"); w }
  ),
  error = function(e) e
)
if (inherits(w, "condition")) {
  cat("class:", paste(class(w), collapse = ","), "\n")
  cat("msg:", conditionMessage(w), "\n")
} else {
  cat("no condition\n")
}
