suppressMessages({ devtools::load_all(".", quiet = TRUE) })
library(dplyr)
con <- entropia_connect("scratch/task31/real-smoke.sqlite")

# Capture warnings instead of letting the default handler print them.
wr <- character()
x <- withCallingHandlers(
  entropia_collect(entropia_llm_results(con)),
  warning = function(w) { wr <<- c(wr, conditionMessage(w)); invokeRestart("muffleWarning") }
)
cat("rows:", nrow(x), "\n")
cat("num warnings captured:", length(wr), "\n")
cat("first warning:", substr(wr[1], 1, 80), "\n")
cat("classes:", class(x$result), "| is list-column:", is.list(x$result), "\n")
entropia_disconnect(con)
cat("LLM COLLECT: PASS\n")
