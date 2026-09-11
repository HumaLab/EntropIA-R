# Explore an EntropIA snapshot in a local dashboard

Builds an optional Shiny application; it does not start a server, open a
browser or open a database connection until a browser session starts.
Prepare a self-contained snapshot with
[`entropia_copy()`](https://humalab.github.io/EntropIA-R/reference/entropia_copy.md)
first. Each session owns a read-only connection and its reactive
results; closing one session never disconnects another. The caller owns
the snapshot file and must retain it until the application stops. Live
refresh and remote authentication are deliberately not provided by this
local application.

## Usage

``` r
entropia_dashboard(
  path,
  title = "EntropIA: explorar el corpus",
  page_size = 25L,
  download_limit = 10000L,
  profile_limit = 1000L
)
```

## Arguments

- path:

  Path to a self-contained SQLite snapshot.

- title:

  Application title.

- page_size:

  Detail rows per page, from 1 to 200.

- download_limit:

  Maximum rows in a dataset download.

- profile_limit:

  Maximum text rows retrieved for an explicit length profile.

## Value

A `shiny.appobj`. Start it with `shiny::runApp(app)`.

## Details

All panels use the same applied selection. Overview calculations
aggregate in SQLite. Detail pagination is server-side. Text is retrieved
only on request; the length panel explicitly profiles at most
`profile_limit` rows, in stable item/asset order, not a representative
random sample. Downloads are bounded by `download_limit` and exclude
paths and metadata. Downloaded text is opt-in. Entity filters affect
entity statistics, not the item universe.

## Examples

``` r
if (interactive() && requireNamespace("shiny", quietly = TRUE) &&
  requireNamespace("bslib", quietly = TRUE) &&
  requireNamespace("ggplot2", quietly = TRUE)) {
  path <- system.file("extdata", "entropia-example.sqlite", package = "entropiaR")
  app <- entropia_dashboard(path)
  shiny::runApp(app)
}
```
