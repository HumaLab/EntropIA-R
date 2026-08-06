suppressMessages({library(tidyselect); library(rlang); library(dplyr); library(tibble)})
df <- tibble(a = 1:3, b = 4:6, created_at = as.POSIXct(c("2026-01-15 12:01:00","2026-01-15 12:03:00","2026-01-15 12:05:00"), tz="UTC"))

f <- function(x, date_var, by = NULL) {
  cat("by expr class: "); print(class(rlang::enquo(by)))
  cat("eval_select date: "); print(tidyselect::eval_select(rlang::enquo(date_var), data = x))
  cat("eval_select by NULL: "); print(tidyselect::eval_select(rlang::enquo(by), data = x))
  cat("eval_select by bare a: "); print(tidyselect::eval_select(rlang::enquo(by), data = x))
}
f(df, created_at)

d <- as.POSIXct(c("2026-01-15 12:01:00", "2026-01-17 12:03:00", "2026-01-19 12:05:00"), tz="UTC")
cutres <- cut(d, "weeks")
cat("cut weeks levels: "); print(levels(cutres))
cat("parsed: "); print(as.POSIXct(as.character(cutres), tz = "UTC"))
cat("month floor: "); print(as.POSIXct(format(d, "%Y-%m-01"), tz = "UTC"))
cat("day floor: "); print(as.POSIXct(format(d, "%Y-%m-%d"), tz = "UTC"))
cat("quarter floor: "); qm <- 1L + 3L * ((as.integer(format(d, "%m")) - 1L) %/% 3L); print(as.POSIXct(sprintf("%04d-%02d-01", as.integer(format(d, "%Y")), qm), tz = "UTC"))
n_words <- function(z) { if (is.na(z)) return(NA_integer_); z <- trimws(z); if (!nzchar(z)) return(0L); lengths(gregexpr("[[:space:]]+", z)) + 1L }
for (s in c("La huelga general de 1920 movilizo a los obreros.", "Compañeros, a la huelga", "", NA_character_)) {
  cat(sprintf("|%s| chars=%s words=%s\n", s, ifelse(is.na(s), "NA", nchar(s)), n_words(s)))
}
