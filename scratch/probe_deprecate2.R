pkgload::load_all("G:/EntropIA-Stack/EntropIA-R", quiet = TRUE)
w <- tryCatch(
  entropiaR:::ent_deprecate("1.0.0", "entropia_old_function()", "entropia_new_function()"),
  warning = function(w) w
)
if (is.null(w)) {
  cat("no warning captured\n")
} else {
  cat("class:", paste(class(w), collapse = ","), "\n")
  cat("msg:", conditionMessage(w), "\n")
}
