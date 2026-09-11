# entropiaR

Interfaz de **solo lectura** entre R y las bases SQLite de
[EntropIA](https://github.com/HumaLab/EntropIA-Pro-Lite).
Estilo tidyverse: explorás el corpus — ítems, textos, entidades, temas,
resultados de LLM — sin escribir SQL.

La base se abre **siempre en lectura**. Nada de este paquete la modifica.

## Camino rápido

```r
library(entropiaR)
library(dplyr)

con <- entropia_connect(system.file(
  "extdata", "entropia-example.sqlite",
  package = "entropiaR"
))

# 1. ¿Qué hay? Agregados en SQLite, sin bajar el texto.
eda <- entropia_overview(con)
eda$counts
eda$collections

# 2. Un dataset reproducible (un universo, una receta).
ds <- entropia_analysis_dataset(
  con,
  asset_type == "pdf",
  name = "pdfs",
  text = FALSE
)
entropia_provenance(ds)$dataset_sha256

# 3. Gráficos sobre las mismas tablas.
entropia_plot_collections(eda$collections)
entropia_plot_entities(eda$entities)
entropia_plot_coverage(eda$quality, metric = "ocr_coverage")

entropia_disconnect(con)
```

Esperado: `eda$counts` informa items/assets/colecciones; el dataset es un
tibble con sello `entropia_prov`; los `entropia_plot_*` devuelven `ggplot`
extensibles con `+`.

## Tu propia base

```r
# Si EntropIA puede estar abierta, snapshot primero (VACUUM INTO, WAL-aware).
live <- entropia_connect("ruta/a/entropia.sqlite")
snap <- tempfile(fileext = ".sqlite")
entropia_copy(live, snap)
entropia_disconnect(live)

con <- entropia_connect(snap)
```

Compatibilidad al abrir (`warn` por defecto):

```r
options(entropiaR.schema_policy = "warn")  # o "error" | "allow"
entropia_schema_compat(con)$compatible
```

Sin las tablas núcleo (`collections`, `items`, `assets`), `warn` y `error`
rechazan la conexión. `allow` abre para diagnóstico.

## EDA compartido

`entropia_overview()` agrega **el universo elegido** en SQL. No materializa
texto ni embeddings.

```r
eda <- entropia_overview(
  con,
  asset_types = c("pdf", "image"),
  page_assets = FALSE
)
eda$quality     # n, total, pct, status, group_id
eda$entities    # n = ocurrencias; pct = prevalencia por item
eda$topics
attr(eda$temporal, "exclusions")
```

`entropia_profile()` perfila un tibble ya recolectado:

```r
lengths <- entropia_text(con) |>
  entropia_collect() |>
  entropia_document_lengths()

entropia_profile(lengths, columns = c("n_chars", "n_words"))
```

Caveats que el paquete no oculta:

| Hecho | Consecuencia |
|---|---|
| Fechas de `created_at` | Son operativas (alta/importación), no necesariamente la fecha del documento |
| `n` de entidades | Ocurrencias; `pct` es prevalencia sobre items del universo |
| Colecciones homónimas | Se distinguen por `collection_id`, no por el nombre |
| Páginas de PDF | Cada página es un asset; un item no es “un documento × N páginas” |
| Entidades de IA | Extracciones, no hechos verificados |

## Dashboard e informe

```r
# No abre el navegador: devuelve un shiny.appobj.
app <- entropia_dashboard(snap)
# shiny::runApp(app)

# Informe HTML congelado (requiere Quarto en PATH).
entropia_report(eda, "estudio.html")              # redacta rutas y etiquetas
entropia_report(eda, "estudio-interno.html", redact = FALSE)
```

Shiny, bslib, ggplot2 y Quarto son **opcionales**. El núcleo (conexión,
corpus, overview, export) funciona sin ellos.

## Qué cubre el paquete

| Capa | Entrada típica |
|---|---|
| Conexión / esquema | `entropia_connect()`, `entropia_copy()`, `entropia_schema_*()`, `entropia_validate()` |
| Tablas perezosas | `entropia_items()`, `entropia_entities()`, … + dplyr |
| Corpus y texto | `entropia_corpus()`, `entropia_text()`, `entropia_metadata()`, `entropia_search()` |
| EDA | `entropia_overview()`, `entropia_profile()` |
| Análisis | `entropia_temporal_profile()`, `entropia_*_frequency()`, `entropia_compare_collections()` |
| Datasets | `entropia_analysis_dataset()`, `entropia_provenance()`, `entropia_export()` |
| Gráficos | `entropia_plot_*()` (Suggests: ggplot2) |
| Apps | `entropia_dashboard()`, `entropia_report()` |

## Documentación

El **español es el idioma principal** (este README y `vignette("connect")`,
etc.). El inglés es la versión secundaria: [README.en.md](README.en.md) y
`vignette("connect.en")`, etc.

Artículos, en orden de uso:

1. `vignette("connect")` — abrir, validar, snapshot
2. `vignette("corpus")` — colecciones, ítems, assets
3. `vignette("text")` — OCR, transcripciones, metadatos
4. `vignette("dplyr")` — filtros perezosos y tipado
5. `vignette("eda")` — overview y profile
6. `vignette("visualize")` — gráficos individuales
7. `vignette("datasets")` — procedencia v2 y exportación
8. `vignette("analysis")` — un análisis completo
9. `vignette("dashboard")` — Shiny y Quarto
10. `vignette("administration")` — solo lectura, WAL, stubs de escritura

Sitio: <https://humalab.github.io/EntropIA-R/>

## Estado

Desarrollo temprano, **v1 solo lectura**. Los stubs `entropia_insert/update/upsert/delete`
fallan con `entropia_error_write_disabled`. Escritura real: v2.

Requiere **R >= 4.1**.

## Licencia

MIT.

---

[English version](README.en.md)
