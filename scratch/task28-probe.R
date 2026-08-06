# Probe: cnd_signal re-raise + lifecycle badge + package load
cat("=== cnd_signal ===", "\n")
cnd <- structure(class = c("my_error", "error", "condition"), list(message = "boom", call = NULL))
res <- tryCatch({ rlang::cnd_signal(cnd); "no-error" }, error = function(e) class(e))
cat("class:", paste(res, collapse = ","), "\n")
msg <- tryCatch(rlang::cnd_signal(cnd), error = function(e) conditionMessage(e))
cat("msg:", msg, "\n")

cat("=== lifecycle badge ===", "\n")
b <- lifecycle::badge("experimental")
cat("badge length:", length(b), "\n")
cat("badge text:", substr(b, 1, 200), "\n")

cat("=== package load_all ===", "\n")
pkgload::load_all("G:/EntropIA-Stack/EntropIA-R", quiet = TRUE)
cat("loaded entropiaR:", as.character(utils::packageVersion("entropiaR")), "\n")
