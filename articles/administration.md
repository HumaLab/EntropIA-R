# Administración segura de los datos

*Versión en español.* English:
[`vignette("administration.en")`](https://humalab.github.io/EntropIA-R/articles/administration.en.md).

## v1 es solo lectura, por diseño

La SQLite de EntropIA no es un almacén plano: 81 triggers (48 de oplog,
33 de actividad de colección) y, a menudo, la app de escritorio abierta.
Un bug de escritura puede romper años de trabajo.

v1 hace las escrituras *imposibles*, no solo desaconsejadas:

``` r

con <- entropia_connect(system.file("extdata", "entropia-example.sqlite", package = "entropiaR"))
```

- flags de solo lectura + `PRAGMA query_only = ON`;
- la API de escritura existe como **stubs** con las firmas de v2, pero
  cada una falla con `entropia_error_write_disabled`;
- `entropia_connect(write = TRUE)` se rechaza en la puerta.

``` r

entropia_insert(con, "items", data.frame(title = "nope"))
#> Error in `ent_write_disabled()`:
#> ! `entropia_insert()` is not available in entropiaR v1.
#> ℹ v1 is read-only: the database may be live in EntropIA (WAL) and is protected
#>   by 81 sync/activity triggers.
#> ℹ Write support ships in v2, where you open the database for writing with
#>   `entropia_connect()` (`path`, `write = TRUE`).
#> ℹ The v2 write design is documented in vignettes/administration.Rmd.
```

``` r

entropia_connect(system.file("extdata", "entropia-example.sqlite", package = "entropiaR"),
  write = TRUE
)
#> Error in `entropia_connect()`:
#> ! Write access is not available in entropiaR v1.
#> ℹ v1 is read-only. Write support ships in v2 -- see
#>   vignettes/administration.Rmd for the design.
```

## WAL y la base viva

Con EntropIA abierta puede haber `-wal` / `-shm`. Leer a través del WAL
es seguro. Dos reglas:

- **Nunca** copies el archivo a mano si hay sidecars; usá
  [`entropia_copy()`](https://humalab.github.io/EntropIA-R/reference/entropia_copy.md)
  (`VACUUM INTO`).
- Si está ocupada,
  [`entropia_connect()`](https://humalab.github.io/EntropIA-R/reference/entropia_connect.md)
  lanza `entropia_error_locked`.

``` r

copy_path <- tempfile(fileext = ".sqlite")
entropia_copy(con, copy_path)
```

## Política de esquema

- `"warn"` (defecto) — avisa en older/newer si el núcleo existe; **sin
  `collections`/`items`/`assets` es error**;
- `"error"` — corta cualquier incompatibilidad;
- `"allow"` — abre en silencio y después
  [`entropia_validate()`](https://humalab.github.io/EntropIA-R/reference/entropia_validate.md).

``` r

entropia_schema_compat(con)$status
#> [1] "known"
entropia_schema_compat(con)$compatible
#> [1] TRUE
```

## Diseño de escritura v2 (aún no implementado)

``` r

entropia_insert(con, table, data, dry_run = TRUE)
entropia_update(con, table, data, by, dry_run = TRUE)
entropia_upsert(con, table, data, by, dry_run = TRUE)
entropia_delete(con, table, filter, all = FALSE, confirm = FALSE)
```

- `dry_run = TRUE` por defecto;
- `upsert` es `INSERT ... ON CONFLICT`, **nunca** `INSERT OR REPLACE`
  (rompe FTS5);
- `delete` de tabla entera pide `all = TRUE` y `confirm = TRUE`;
- todo transaccional y parametrizado.

Hoy: la base es input inmutable. Administrala con EntropIA, snapshot con
[`entropia_copy()`](https://humalab.github.io/EntropIA-R/reference/entropia_copy.md),
y `entropiaR` no puede corromperla.

``` r

entropia_disconnect(con)
```

English:
[`vignette("administration.en")`](https://humalab.github.io/EntropIA-R/articles/administration.en.md).
