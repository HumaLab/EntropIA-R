# Conectar una base EntropIA

*Versión en español.* English:
[`vignette("connect.en")`](https://humalab.github.io/EntropIA-R/articles/connect.en.md).

## Solo lectura, por diseño

EntropIA guarda el corpus en SQLite. `entropiaR` es la interfaz tidy y
tipada, y en v1 es **solo lectura de construcción**:
[`entropia_connect()`](https://humalab.github.io/EntropIA-R/reference/entropia_connect.md)
abre el archivo con flags de lectura y reafirma
`PRAGMA query_only = ON`. Nada de este paquete puede modificar la base.
Es deliberado: la base puede estar *viva* bajo la app de escritorio
(WAL, motor de sync, 81 triggers).

``` r

# Pedir escritura falla en v1.
entropia_connect(system.file("extdata", "entropia-example.sqlite", package = "entropiaR"),
  write = TRUE
)
#> Error in `entropia_connect()`:
#> ! Write access is not available in entropiaR v1.
#> ℹ v1 is read-only. Write support ships in v2 -- see
#>   vignettes/administration.Rmd for the design.
```

## Abrir una conexión

El paquete trae una base de ejemplo. Conectala así:

``` r

con <- entropia_connect(system.file("extdata", "entropia-example.sqlite", package = "entropiaR"))
con
#> <SQLiteConnection>
#>   Path: /home/runner/work/_temp/Library/entropiaR/extdata/entropia-example.sqlite
#>   Extensions: TRUE
```

El resultado es un `entropia_conn`: un `SQLiteConnection` de DBI, con
ruta, modo, versión de esquema y **hash de esquema** (DDL + migraciones,
no el contenido de las filas):

``` r

class(con)
#> [1] "entropia_conn"
#> attr(,"package")
#> [1] "entropiaR"
summary(con)
#> entropiaR connection summary
#>   path:           /home/runner/work/_temp/Library/entropiaR/extdata/entropia-example.sqlite
#>   mode:           read-only
#>   schema version: 0029_rag_chunks
#>   schema hash:    09d4c603b66d68c4c0cef0f51ff09a04fb30a49fe200907ef69693d11dd25732
#>   valid:          TRUE
DBI::dbIsValid(con)
#> [1] TRUE
```

Tu base de EntropIA se abre igual:

``` r

con <- entropia_connect("ruta/a/entropia.sqlite")
```

El archivo tiene que existir y ser SQLite. Si falta o no es SQLite, el
error es tipado:

``` r

entropia_connect("no/such/database.sqlite")
#> Error in `entropia_connect()`:
#> ! Database file not found: no/such/database.sqlite.
#> ℹ Create the database with the EntropIA desktop app first, or pass a different
#>   path.
```

``` r

notsqlite <- tempfile(fileext = ".txt")
writeLines("not a database", notsqlite)
entropia_connect(notsqlite)
#> Error in `entropia_connect()`:
#> ! /tmp/Rtmp9q2k4P/file207574072242.txt is not a SQLite database.
#> ℹ entropiaR reads EntropIA SQLite databases. The file does not begin with the
#>   SQLite header.
```

## Versión de esquema

No hay versión numérica. La autoridad es la fila más nueva de
`_migrations`:

``` r

entropia_schema_version(con)
#> [1] "0029_rag_chunks"
```

[`entropia_schema_compat()`](https://humalab.github.io/EntropIA-R/reference/entropia_schema_compat.md)
clasifica la base (`known`, `newer`, `older`, `unknown`) y lista
columnas faltantes:

``` r

compat <- entropia_schema_compat(con)
compat$status
#> [1] "known"
compat$compatible
#> [1] TRUE
```

[`entropia_schema_info()`](https://humalab.github.io/EntropIA-R/reference/entropia_schema_info.md)
lista tablas legibles, presencia real, tipo esperado y tipo SQLite vivo:

``` r

schema <- entropia_schema_info(con)
head(schema, 10)
#> # A tibble: 10 × 9
#>    table    column type  required contract min_version source presence live_type
#>    <chr>    <chr>  <chr> <lgl>    <chr>    <chr>       <chr>  <lgl>    <chr>    
#>  1 _migrat… id     INTE… TRUE     NA       0001_initi… manif… TRUE     INTEGER  
#>  2 _migrat… name   TEXT  TRUE     NA       0001_initi… manif… TRUE     TEXT     
#>  3 _migrat… appli… INTE… TRUE     datetim… 0001_initi… manif… TRUE     INTEGER  
#>  4 annotat… id     TEXT  TRUE     NA       0007_annot… manif… TRUE     TEXT     
#>  5 annotat… asset… TEXT  TRUE     NA       0007_annot… manif… TRUE     TEXT     
#>  6 annotat… page   INTE… TRUE     int      0007_annot… manif… TRUE     INTEGER  
#>  7 annotat… kind   TEXT  TRUE     enum     0007_annot… manif… TRUE     TEXT     
#>  8 annotat… color  TEXT  TRUE     NA       0007_annot… manif… TRUE     TEXT     
#>  9 annotat… x      REAL  TRUE     dbl      0007_annot… manif… TRUE     REAL     
#> 10 annotat… y      REAL  TRUE     dbl      0007_annot… manif… TRUE     REAL
```

## Estado compacto

``` r

entropia_status(con)
#> entropiaR status
#>   path:           /home/runner/work/_temp/Library/entropiaR/extdata/entropia-example.sqlite
#>   mode:           read-only
#>   schema version: 0029_rag_chunks
#>   valid:          TRUE
#>   row counts:     _migrations=29, sync_meta=8, assets=5, entities=4, app_settings=3 (+26 more)
#>   sync:           last_sync_at 2026-01-15 12:13:20, capture_enabled TRUE
#>   journal:        delete
#>   wal sidecar:    FALSE
```

## Política de compatibilidad

`options(entropiaR.schema_policy)`:

- `"warn"` (defecto) — avisa y sigue en esquemas older/newer **si
  existen** las tablas núcleo `collections`, `items` y `assets`;
- `"error"` — corta ante cualquier incompatibilidad, incluida un núcleo
  ausente;
- `"allow"` — abre igual para poder correr
  [`entropia_validate()`](https://humalab.github.io/EntropIA-R/reference/entropia_validate.md).

Un SQLite que solo tiene `_migrations` **no** es compatible.

``` r

options(entropiaR.schema_policy = "warn")
entropia_schema_info(con) |>
  utils::head(8)
#> # A tibble: 8 × 9
#>   table     column type  required contract min_version source presence live_type
#>   <chr>     <chr>  <chr> <lgl>    <chr>    <chr>       <chr>  <lgl>    <chr>    
#> 1 _migrati… id     INTE… TRUE     NA       0001_initi… manif… TRUE     INTEGER  
#> 2 _migrati… name   TEXT  TRUE     NA       0001_initi… manif… TRUE     TEXT     
#> 3 _migrati… appli… INTE… TRUE     datetim… 0001_initi… manif… TRUE     INTEGER  
#> 4 annotati… id     TEXT  TRUE     NA       0007_annot… manif… TRUE     TEXT     
#> 5 annotati… asset… TEXT  TRUE     NA       0007_annot… manif… TRUE     TEXT     
#> 6 annotati… page   INTE… TRUE     int      0007_annot… manif… TRUE     INTEGER  
#> 7 annotati… kind   TEXT  TRUE     enum     0007_annot… manif… TRUE     TEXT     
#> 8 annotati… color  TEXT  TRUE     NA       0007_annot… manif… TRUE     TEXT
```

## Validar

[`entropia_validate()`](https://humalab.github.io/EntropIA-R/reference/entropia_validate.md)
diagnostica estructura: tablas núcleo, columnas requeridas, recuentos,
base vacía. Un tibble vacío de hallazgos es un OK:

``` r

findings <- entropia_validate(con)
findings
#> # A tibble: 0 × 5
#> # ℹ 5 variables: severity <chr>, kind <chr>, table <chr>, column <chr>,
#> #   message <chr>
```

## Snapshot para análisis largos

Si vas a trabajar rato, copiá primero con
[`entropia_copy()`](https://humalab.github.io/EntropIA-R/reference/entropia_copy.md).
Usa `VACUUM INTO`: lee a través del WAL y escribe un archivo
autocontenido.

``` r

copy_path <- tempfile(fileext = ".sqlite")
entropia_copy(con, copy_path)
copy_con <- entropia_connect(copy_path)
entropia_status(copy_con)$row_counts
#>               _migrations                 sync_meta                    assets 
#>                        29                         8                         5 
#>                  entities              app_settings                 fts_items 
#>                         4                         3                         3 
#>                     items               extractions               item_topics 
#>                         3                         2                         2 
#>                     notes              rag_messages         sync_row_versions 
#>                         2                         2                         2 
#>                    topics               annotations               collections 
#>                         2                         1                         1 
#>                   layouts               llm_results rag_asset_embedding_state 
#>                         1                         1                         1 
#>                rag_chunks            rag_chunks_fts         rag_conversations 
#>                         1                         1                         1 
#>            sync_conflicts            transcriptions                   triples 
#>                         1                         1                         1 
#>                vec_assets           sync_blob_index                sync_oplog 
#>                         1                         0                         0 
#>        sync_pending_blobs          sync_pending_fts         sync_pending_rows 
#>                         0                         0                         0 
#>        sync_topic_aliases 
#>                         0
entropia_disconnect(copy_con)
```

## Cerrar

[`entropia_disconnect()`](https://humalab.github.io/EntropIA-R/reference/entropia_disconnect.md)
es idempotente:

``` r

entropia_disconnect(con)
DBI::dbIsValid(con)
#> [1] FALSE
```

Siguiente:
[`vignette("corpus")`](https://humalab.github.io/EntropIA-R/articles/corpus.md).
English:
[`vignette("connect.en")`](https://humalab.github.io/EntropIA-R/articles/connect.en.md).
