# Dashboard local e informes congelados

*Versión en español.* English:
[`vignette("dashboard.en")`](https://humalab.github.io/EntropIA-R/articles/dashboard.en.md).

El dashboard y el informe Quarto **reutilizan** las tablas de
[`entropia_overview()`](https://humalab.github.io/EntropIA-R/reference/entropia_overview.md).
No hay un segundo juego de métricas.

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

Apuntá la app a un **snapshot autocontenido**. Un `-wal` no vacío se
rechaza: no es un visor en vivo de la app de escritorio.

## Armar la app (no abre el navegador)

``` r

app <- entropia_dashboard(snap)
class(app)
#> [1] "shiny.appobj"
```

Devuelve un `shiny.appobj`. El servidor se arranca aparte:

``` r

shiny::runApp(app)
```

Hace falta Suggests: `shiny`, `bslib` y `ggplot2`.

## Qué hace la app

| Panel       | Comportamiento                                           |
|-------------|----------------------------------------------------------|
| Resumen     | Esquema, recuentos, colecciones, inventario              |
| Calidad     | Tasas con `n` / `total` / `status`                       |
| Exploración | Temporal, entidades, temas; perfil de longitudes acotado |
| Detalle     | Páginas del universo en el servidor; texto a pedido      |
| Exportación | CSV + JSON de procedencia (rutas redactadas) + EDA + PNG |

**Aplicar filtros** fija el universo. Las colecciones se eligen por ID.
Fuente / modelo / confianza de entidades afectan solo las tablas de
entidades.

Cada sesión Shiny abre su conexión de solo lectura y la cierra en
`session$onSessionEnded`.

## Informe Quarto congelado

``` r

con <- entropia_connect(snap)
eda <- entropia_overview(con)
entropia_disconnect(con)
```

``` r

# Requiere el ejecutable `quarto` en PATH, más ggplot2/knitr/rmarkdown.
entropia_report(eda, "estudio.html")               # redacta rutas y etiquetas
entropia_report(eda, "estudio-interno.html", redact = FALSE)
```

El HTML no consulta SQLite del lector. `redact = TRUE` (defecto) saca
`source_path` y reemplaza etiquetas. Los agregados igual pueden revelar
información: revisá antes de compartir. Destinos existentes no se pisan.

## Avisos en la UI

- Timestamps operativos ≠ fechas del documento.
- Entidades de IA no son hechos verificados.
- El perfil de longitudes son las primeras N filas en orden estable, no
  una muestra aleatoria.

Siguiente:
[`vignette("administration")`](https://humalab.github.io/EntropIA-R/articles/administration.md).
English:
[`vignette("dashboard.en")`](https://humalab.github.io/EntropIA-R/articles/dashboard.en.md).
