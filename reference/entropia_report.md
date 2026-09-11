# Render a frozen, shareable EDA dashboard with Quarto

Renders the tables returned by
[`entropia_overview()`](https://humalab.github.io/EntropIA-R/reference/entropia_overview.md)
as a standalone HTML dashboard using the bundled Quarto template. It
does not query SQLite, recompute metrics, start a Shiny server or
include document text. Quarto must be installed separately and available
on `PATH`; `ggplot2`, `knitr` and `rmarkdown` are optional rendering
dependencies. Existing destination files are never overwritten.
Temporary rendering files are removed on exit.

## Usage

``` r
entropia_report(x, path, redact = TRUE)
```

## Arguments

- x:

  The complete list returned by
  [`entropia_overview()`](https://humalab.github.io/EntropIA-R/reference/entropia_overview.md).

- path:

  Destination HTML file in an existing directory.

- redact:

  Whether to remove paths and replace identifying labels.

## Value

Normalized output path, invisibly, after successful rendering.

## Details

By default source paths and collection filters are removed, and
collection, entity and topic labels are replaced with report-local
labels. Aggregated values can still disclose information: review every
report before sharing. The redacted report is a presentation artifact,
not a complete replay recipe. Use `redact = FALSE` only for a trusted
audience.

## Examples

``` r
if (FALSE) { # \dontrun{
con <- entropia_connect("study-snapshot.sqlite")
eda <- entropia_overview(con)
entropia_disconnect(con)
entropia_report(eda, "study.html")
} # }
```
