# entropiaR

A tidyverse-style, **read-only** R interface to the SQLite database generated
by the [EntropIA](https://github.com/HLab-MITI/EntropIA) desktop application.
It provides lazy table access via `dbplyr`, typed collection with automatic
timestamp and JSON handling, parameter-safe full-text search, corpus and
metadata helpers, corpus quality diagnostics, analysis helpers, and
reproducible export with provenance.

## Getting started

```r
# The package ships a small example database for trying things out.
con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
                                    package = "entropiaR"))

entropia_items(con)                      # lazy tbl_sql, nothing loaded yet
entropia_collect(entropia_items(con))    # typed tibble: POSIXct, JSON list-cols
entropia_search(con, "huelga")           # parameter-safe FTS5 search
entropia_corpus(con) |> entropia_collect() |> entropia_document_lengths()
entropia_disconnect(con)
```

Connect to your own EntropIA database the same way:
`entropia_connect("path/to/entropia.sqlite")`. The connection is read-only and
runs a schema-compatibility check on open (`options(entropiaR.schema_policy)`
controls the policy).

## Status

Early development. The package is currently **read-only** (v1): it opens the
EntropIA SQLite database for querying only and never writes to it. The write
API is designed and stubbed with clear errors; full implementation is v2.

## Development setup

- **R >= 4.1** is required; this package is tested with **R 4.5.2**.
- **Windows**: R is typically *not* on PATH. Either add `C:\Program Files\R\R-4.5.2\bin`
  to your PATH, or invoke R by full path, e.g.
  `"C:\Program Files\R\R-4.5.2\bin\Rscript.exe" -e "..."`.
- Install development dependencies:
  `install.packages(c("devtools", "roxygen2", "testthat", "usethis", "lintr", "styler", "covr", "pkgdown", "rmarkdown", "knitr", "spelling"))`
  The full test suite also needs optional Suggests: `install.packages(c("ggplot2", "arrow", "bit64", "vdiffr", "tidyr", "lubridate", "forcats"))`
- Common commands:
  - `devtools::load_all()` — load the package in the current session
  - `devtools::test()` — run the testthat suite
  - `devtools::check()` — full package check (must finish with 0 errors)
  - `pkgdown::build_site()` — build the documentation site
