# entropiaR

A tidyverse-style, **read-only** R interface to the SQLite database generated
by the [EntropIA](https://github.com/HLab-MITI/EntropIA) desktop application.
It provides lazy table access via `dbplyr`, typed collection with automatic
timestamp and JSON handling, parameter-safe full-text search, corpus and
metadata helpers, corpus quality diagnostics, analysis helpers, and
reproducible export with provenance.

## Status

Early development. The package is currently **read-only** (v1): it opens the
EntropIA SQLite database for querying only and never writes to it.

## Development setup

- **R >= 4.1** is required; this package is tested with **R 4.5.2**.
- **Windows**: R is typically *not* on PATH. Either add `C:\Program Files\R\R-4.5.2\bin`
  to your PATH, or invoke R by full path, e.g.
  `"C:\Program Files\R\R-4.5.2\bin\Rscript.exe" -e "..."`.
- Install development dependencies:
  `install.packages(c("devtools", "roxygen2", "testthat", "usethis", "lintr", "styler", "covr"))`
- Common commands:
  - `devtools::load_all()` — load the package in the current session
  - `devtools::test()` — run the testthat suite
  - `devtools::check()` — full package check (must finish with 0 errors)