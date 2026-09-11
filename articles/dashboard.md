# Local dashboard and frozen reports

The dashboard and the Quarto report **reuse**
[`entropia_overview()`](https://humalab.github.io/EntropIA-R/reference/entropia_overview.md)
tables. They do not implement a second set of metrics.

``` r

example <- system.file(
  "extdata", "entropia-example.sqlite",
  package = "entropiaR"
)
con <- entropia_connect(example)
snap <- tempfile(fileext = ".sqlite")
entropia_copy(con, snap)
entropia_disconnect(con)
```

Always point the app at a **self-contained snapshot**
([`entropia_copy()`](https://humalab.github.io/EntropIA-R/reference/entropia_copy.md)).
A nonempty `-wal` sidecar is rejected: the dashboard is not a live
viewer of the desktop app.

## Build the app (does not open a browser)

``` r

app <- entropia_dashboard(snap)
class(app)
#> [1] "shiny.appobj"
```

[`entropia_dashboard()`](https://humalab.github.io/EntropIA-R/reference/entropia_dashboard.md)
returns a `shiny.appobj`. Starting the server is explicit:

``` r

shiny::runApp(app)
```

Requires Suggests packages `shiny`, `bslib` and `ggplot2`.

## What the app does

| Panel       | Behaviour                                                   |
|-------------|-------------------------------------------------------------|
| Resumen     | Schema, counts, collections, inventory                      |
| Calidad     | Rates with `n` / `total` / `status`                         |
| Exploración | Temporal, entities, topics; optional bounded length profile |
| Detalle     | Server-side pages of the universe; text loaded on demand    |
| Exportación | CSV + provenance JSON (paths redacted) + EDA JSON + PNG     |

One **Apply** button commits filters. Collection filters use IDs, so two
folders named “Archivo” do not collapse. Entity source / model /
confidence affect entity tables only, not the item universe.

Each Shiny session opens its own read-only connection and ends it on
`session$onSessionEnded`. Closing one browser tab does not disconnect
another session.

## Frozen Quarto report

``` r

con <- entropia_connect(snap)
eda <- entropia_overview(con)
entropia_disconnect(con)
```

``` r

# Requires the `quarto` executable on PATH, plus ggplot2/knitr/rmarkdown.
entropia_report(eda, "estudio.html")               # redacts paths and labels
entropia_report(eda, "estudio-interno.html", redact = FALSE)
```

The HTML is a snapshot of *already computed* tables. It will not query a
reader’s local SQLite file. `redact = TRUE` (default) drops
`source_path` and replaces collection / entity / topic labels with
report-local names. Aggregates can still disclose information — review
before sharing.

Existing destinations are never overwritten
(`entropia_error_dest_exists`).

## Caveats shown in the UI

- Operational timestamps ≠ document dates.
- AI-extracted entities are not verified facts.
- Length profiles are the first N rows in stable order, not a random
  sample.

Next:
[`vignette("administration")`](https://humalab.github.io/EntropIA-R/articles/administration.md)
for WAL, locks and the write stubs.
