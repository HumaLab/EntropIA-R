suppressMessages({ library(devtools) })
load_all(".", quiet = TRUE)
options(entropiaR.schema_policy = "allow")

con <- entropia_connect("scratch/entropia-snapshot.sqlite")
on.exit(try(entropia_disconnect(con), silent = TRUE), add = TRUE)

cat("schema:", entropia_schema_version(con), "\n")

# corpus: one row per asset, no BLOB, text + metadata + collection name
cp <- entropia_corpus(con)
sql <- as.character(dbplyr::sql_render(cp))
cat("SQL render has joins:", grepl("JOIN", sql), "| has BLOB:", grepl("embedding", sql), "\n")
res <- dplyr::collect(cp)
cat("corpus rows (assets):", nrow(res), "\n")
cat("cols:", paste(names(res), collapse=", "), "\n")
cat("has text:", "text" %in% names(res), "| has metadata:", "metadata" %in% names(res), "| has collection_name:", "collection_name" %in% names(res), "\n")
cat("distinct collections:", length(unique(res$collection_name)), "\n")
cat("non-NA text:", sum(!is.na(res$text)), "\n")
cat("text col type:", class(res$text), "\n")

# collection filter
names_ <- unique(res$collection_name)
if (length(names_) >= 1) {
  cp1 <- dplyr::collect(entropia_corpus(con, collections = names_[1]))
  cat("filtered to", names_[1], "->", nrow(cp1), "rows, all collection_name == target:", all(cp1$collection_name == names_[1]), "\n")
}

# asset_types filter
types <- sort(unique(res$asset_type))
cat("asset types:", paste(types, collapse=", "), "\n")
img <- dplyr::collect(entropia_corpus(con, asset_types = "image"))
cat("image rows:", nrow(img), "\n")

# page_assets toggle
top <- dplyr::collect(entropia_corpus(con, page_assets = FALSE))
cat("page_assets=FALSE rows:", nrow(top), "vs all:", nrow(res), "\n")

# metadata
m <- entropia_metadata(con)
cat("metadata rows:", nrow(m), "\n")
cat("metadata cols:", paste(names(m), collapse=", "), "\n")
cat("non-NA original_name:", sum(!is.na(m$original_name)), "\n")
cat("imported_at class:", class(m$imported_at), "\n")
cat("sample imported_at:", as.character(m$imported_at[which(!is.na(m$imported_at))[1]]), "\n")
cat("list cols:", paste(names(m)[vapply(m, is.list, logical(1))], collapse=", "), "\n")
