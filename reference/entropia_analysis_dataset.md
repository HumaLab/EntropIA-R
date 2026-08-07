# Build a reproducible analysis dataset

**\[experimental\]**

## Usage

``` r
entropia_analysis_dataset(con, ..., name = NULL)
```

## Arguments

- con:

  A connection returned by
  [`entropia_connect()`](https://github.com/HumaLab/EntropIA-R/reference/entropia_connect.md).

- ...:

  Filter expressions applied to the corpus, e.g.
  `asset_type == "image"`. Column names resolve against the lazy corpus
  (see
  [`entropia_corpus()`](https://github.com/HumaLab/EntropIA-R/reference/entropia_corpus.md)
  for the full column set). Must be unnamed.

- name:

  Optional human-readable label stored in the provenance.

## Value

A
[`tibble::tibble()`](https://tibble.tidyverse.org/reference/tibble.html)
of class `entropia_dataset`, one row per asset, with the `entropia_prov`
attribute.

## Details

The dataset boundary of the package: assembles the lazy corpus
([`entropia_corpus()`](https://github.com/HumaLab/EntropIA-R/reference/entropia_corpus.md)),
applies any filter expressions passed in `...`, and materialises the
result with a deterministic row order (arranged by `asset_id`). The
returned tibble carries class `entropia_dataset` and an `entropia_prov`
attribute recording everything needed to reconstruct the dataset:

- `name`: the human label passed to `name` (`NULL` for unnamed);

- `schema_version`: the database schema head (e.g. `"0029_rag_chunks"`);

- `content_hash`: the connection's schema content hash (see
  [`entropia_connect()`](https://github.com/HumaLab/EntropIA-R/reference/entropia_connect.md));

- `source_path`: the database file the dataset was built from;

- `filters`: the deparsed filter expressions captured from `...`;

- `package_version`: the entropiaR version used;

- `built_at`: the build timestamp (ISO-8601, UTC);

- `r_version`: the R version used.

Building the same dataset twice against an unchanged database yields
byte-identical rows (deterministic ordering) and identical provenance
apart from `built_at`. Read the stamp with
[`entropia_provenance()`](https://github.com/HumaLab/EntropIA-R/reference/entropia_provenance.md)
and persist it as a JSON sidecar with
[`entropia_write_provenance()`](https://github.com/HumaLab/EntropIA-R/reference/entropia_write_provenance.md).

## Examples

``` r
con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
  package = "entropiaR"
))
ds <- entropia_analysis_dataset(con, asset_type == "pdf", name = "PDF corpus")
entropia_provenance(ds)
#> entropiaR dataset provenance
#>   name:           PDF corpus
#>   schema version: 0029_rag_chunks
#>   content hash:   09d4c603b66d68c4c0cef0f51ff09a04fb30a49fe200907ef69693d11dd25732
#>   source path:    /home/runner/work/_temp/Library/entropiaR/extdata/entropia-example.sqlite
#>   filters:        asset_type == "pdf"
#>   package:        0.0.0.9000
#>   built at:       2026-08-07T00:07:02.278Z
#>   R version:      R version 4.6.1 (2026-06-24)
entropia_disconnect(con)
```
