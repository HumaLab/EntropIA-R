library(devtools)
devtools::load_all("G:/EntropIA-Stack/EntropIA-R", quiet = TRUE)
con <- entropia_connect("G:/EntropIA-Stack/EntropIA-R/scratch/entropia-accept22.sqlite", quiet = TRUE)
on.exit(entropia_disconnect(con), add = TRUE)

cat("schema_version:", attr(con, "schema_version"), "\n")
ds1 <- entropia_analysis_dataset(con, asset_type == "image", name = "accept")
ds2 <- entropia_analysis_dataset(con, asset_type == "image", name = "accept")

cat("rows:", nrow(ds1), "\n")
p1 <- entropia_provenance(ds1)
p2 <- entropia_provenance(ds2)
cat("identical content hash:", identical(p1$content_hash, p2$content_hash), "\n")
cat("identical filters:", identical(p1$filters, p2$filters), "\n")
cat("identical schema:", identical(p1$schema_version, p2$schema_version), "\n")
cat("identical package:", identical(p1$package_version, p2$package_version), "\n")
d1 <- as.data.frame(ds1); d2 <- as.data.frame(ds2)
attr(d1, "entropia_prov") <- NULL; attr(d2, "entropia_prov") <- NULL
cat("identical rows (data only):", identical(d1, d2), "\n")

# JSON round-trip on the real DB dataset
path <- tempfile(fileext = ".json")
entropia_write_provenance(ds1, path)
rt <- jsonlite::fromJSON(path)
cat("json round-trip identical:", identical(unclass(p1), rt), "\n")

cat("hash:", substr(p1$content_hash, 1, 16), "...\n")
cat("filters:", p1$filters, "\n")
cat("ACCEPTANCE DONE\n")
