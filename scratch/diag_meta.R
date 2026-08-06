pkgload::load_all("G:/EntropIA-Stack/EntropIA-R", quiet = TRUE)
Sys.setenv(NOT_CRAN = "true")
path <- ent_fixture("full")
cat("fixture path:", path, "\n")
wcon <- DBI::dbConnect(RSQLite::SQLite(), path)
r <- DBI::dbExecute(
  wcon,
  "UPDATE items SET metadata = '{\"bad\": '
   WHERE id = (SELECT id FROM items WHERE metadata IS NOT NULL LIMIT 1)"
)
cat("update rows:", r, "\n")
DBI::dbDisconnect(wcon)
con <- entropia_connect(path)
cat("connected\n")
w <- tryCatch(
  withCallingHandlers(entropia_metadata(con), warning = function(w) {
    cat("WARNING class:", paste(class(w), collapse = ","), "\n")
    cat("WARNING msg:", conditionMessage(w), "\n")
    invokeRestart("muffleWarning")
  }),
  error = function(e) {
    cat("ERROR class:", paste(class(e), collapse = ","), "\n")
    cat("ERROR msg:", conditionMessage(e), "\n")
    NULL
  }
)
entropia_disconnect(con)
cat("done\n")
