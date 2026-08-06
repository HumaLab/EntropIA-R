suppressMessages({
  pkgload::load_all("G:/EntropIA-Stack/EntropIA-R", quiet = TRUE)
  library(dplyr)
})
src <- "G:/EntropIA-Stack/EntropIA-R/tests/testthat/fixtures/full.sqlite"
dest <- tempfile(fileext = ".sqlite")
file.copy(src, dest, overwrite = TRUE)
con <- entropiaR::entropia_connect(dest)
items <- entropia_collect(entropia_items(con))
cat("items created_at:\n"); print(items$created_at)
cat("class:", class(items$created_at), "\n")

txt <- dplyr::collect(entropia_text(con))
cat("text rows:\n"); print(txt[, c("id", "type", "text")])
nw <- vapply(txt$text, function(z) if (is.na(z)) NA_integer_ else { z <- trimws(z); if (!nzchar(z)) 0L else lengths(gregexpr("[[:space:]]+", z)) + 1L }, integer(1))
cat("nchar/words per text row:\n")
for (i in seq_len(nrow(txt))) cat(sprintf("  %s: nchar=%s words=%s\n", txt$id[i], if (is.na(txt$text[i])) "NA" else nchar(txt$text[i]), nw[i]))

cor <- dplyr::collect(entropia_corpus(con))
cat("corpus cols:", paste(names(cor), collapse = ", "), "\n")
cat("corpus asset_created_at class:", class(cor$asset_created_at), "\n")
cat("corpus asset_created_at:", paste(head(cor$asset_created_at), collapse = ", "), "\n")
entropia_disconnect(con)
