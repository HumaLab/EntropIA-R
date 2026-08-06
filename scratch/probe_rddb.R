pkgload::load_all("G:/EntropIA-Stack/EntropIA-R", quiet = TRUE)
db <- tryCatch(tools::Rd_db("entropiaR"), error = function(e) e)
if (inherits(db, "condition")) {
  cat("Rd_db error:", conditionMessage(db), "\n")
} else {
  cat("Rd_db keys (first 5):", paste(head(names(db), 5), collapse = ", "), "\n")
  rd <- db[["entropia_temporal_profile.Rd"]]
  txt <- paste(capture.output(tools::Rd2txt(rd)), collapse = "\n")
  cat("badge Experimental:", grepl("Experimental", txt, fixed = TRUE), "\n")
}
