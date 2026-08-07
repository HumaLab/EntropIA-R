# entropiaR

Interfaz de **solo lectura** entre R y las bases de datos SQLite generadas por la
aplicación de escritorio [EntropIA](https://github.com/HumaLab/EntropIA-Pro-Lite).
Con estilo tidyverse: explorás tu corpus documental completo — ítems, transcripciones,
entidades, análisis de LLM, búsquedas — sin escribir una sola línea de SQL.

Todo acceso es perezoso (`tbl_sql` vía `dbplyr`), tipado al materializar
(timestamps a `POSIXct`, JSON a list-columns) y respaldado por chequeos de
compatibilidad de esquema contra la base real. Y por diseño: la base se abre
**en modo lectura**, nunca se modifica.

## Características

- **Acceso perezoso a 18 tablas**: `entropia_items()`, `entropia_entities()`,
  `entropia_transcriptions()`, `entropia_llm_results()`, y más. Componé con los
  verbos de `dplyr` y materializá con `entropia_collect()`.
- **Materialización tipada**: columnas de timestamps a `POSIXct` (con manejo
  automático de ms/segundos) y columnas JSON a list-columns.
- **Búsqueda full-text** (FTS5) parametrizada y segura: `entropia_search()`.
- **Capa de dominio**: corpus unificado con el mejor texto disponible,
  metadatos parseados y helpers de extracción de texto.
- **Diagnóstico del corpus**: cobertura OCR/metadatos, detección de referencias
  huérfanas y validación de la conexión.
- **Análisis listos para usar**: perfiles temporales, longitudes de documentos,
  frecuencias de entidades y temas, comparación entre colecciones, y datasets
  reproducibles con procedencia.
- **Visualización** con `ggplot2` (`entropia_plot_*`) y **exportación
  reproducible** a CSV, TSV, JSON, RDS, Parquet o Arrow, con sidecars de
  procedencia.

## Instalación

```r
remotes::install_github("HumaLab/EntropIA-R")
```

Requiere **R >= 4.1**.

## Uso rápido

```r
library(entropiaR)

# El paquete incluye una base de ejemplo para probar sin instalar nada más.
con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
                                    package = "entropiaR"))

entropia_items(con)                          # tbl_sql perezoso: nada cargado aún
entropia_collect(entropia_items(con))        # tibble tipado: POSIXct + list-columns JSON
entropia_search(con, "huelga")               # búsqueda full-text segura (FTS5)
entropia_corpus(con) |> entropia_collect() |> entropia_document_lengths()

entropia_disconnect(con)
```

## Conectar tu propia base

Si usás la aplicación EntropIA, conectá la base que genera con la misma
llamada:

```r
con <- entropia_connect("ruta/a/tu/entropia.sqlite")
```

La conexión es de solo lectura y, al abrir, corre un chequeo de compatibilidad
de esquema contra la base real (el comportamiento se controla con
`options(entropiaR.schema_policy = "warn" | "error" | "allow")`).

## Documentación

- [Sitio web del paquete](https://humalab.github.io/EntropIA-R/) con reference y
  vignettes en español: conexión, corpus, texto, dplyr, datasets, análisis y
  administración.
- Ayuda en R: `?entropia_connect`, `?entropia_search`, etc.

## Estado del proyecto

Desarrollo temprano. La versión actual (v1) es **solo lectura**: abre la base
para consultarla y nunca la escribe. La API de escritura ya está diseñada y
disponible como stubs con errores claros; su implementación completa llega con
la v2.

## Licencia

MIT.

---

[English version](https://github.com/HumaLab/EntropIA-R/blob/main/README.en.md)
