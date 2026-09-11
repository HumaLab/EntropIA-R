# Safe data administration

*English version.* Spanish:
[`vignette("administration")`](https://humalab.github.io/EntropIA-R/articles/administration.md).

## v1 is read-only, by design

The EntropIA SQLite database is not a plain table store. It is guarded
by a sync engine and **81 triggers** (48 oplog-capture triggers maintain
`sync_row_versions`, and 33 collection-activity triggers maintain
`collections.updated_at`), and it may be *live* under the EntropIA
desktop app at the moment you connect. A bug in a write path could
corrupt a database that took years to build.

So v1 makes writes impossible rather than merely discouraged:

``` r

con <- entropia_connect(system.file("extdata", "entropia-example.sqlite", package = "entropiaR"))
```

- the connection is opened with SQLite’s read-only flags and
  `PRAGMA query_only = ON` is re-asserted on open;
- the write API exists as **stubs** with the v2 signatures, but every
  one errors with `entropia_error_write_disabled` before touching the
  database;
- `entropia_connect(write = TRUE)` is rejected at the door.

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

Every stub error message names the verb, states that v1 is read-only,
points at the v2 plan, and suggests
`entropia_connect(path, write = TRUE)` for v2.

## WAL and the live database

While EntropIA runs, the database may have `-wal` and `-shm` sidecar
files and be journaling in WAL mode. Reading through WAL is safe — a
read-only client sees a consistent snapshot. Two practical rules:

- **Never** copy the database with a file copy while sidecars exist; use
  [`entropia_copy()`](https://humalab.github.io/EntropIA-R/reference/entropia_copy.md),
  which reads *through* the sidecars and emits one self-contained
  snapshot via `VACUUM INTO`.
- If the database is busy,
  [`entropia_connect()`](https://humalab.github.io/EntropIA-R/reference/entropia_connect.md)
  raises `entropia_error_locked` with guidance to retry or snapshot.

``` r

copy_path <- tempfile(fileext = ".sqlite")
entropia_copy(con, copy_path)
```

## Schema compatibility policy

Because the database evolves, the package checks the schema on open and
acts on `options(entropiaR.schema_policy)`:

- `"warn"` (default) — warn and proceed for older/newer schemas when
  core tables exist; **missing `collections`/`items`/`assets` is an
  error**;
- `"error"` — hard stop on any incompatibility;
- `"allow"` — silent open, then inspect with
  [`entropia_validate()`](https://humalab.github.io/EntropIA-R/reference/entropia_validate.md).

``` r

entropia_schema_compat(con)$status
#> [1] "known"
entropia_schema_compat(con)$compatible
#> [1] TRUE
```

## The v2 write design

Full write support is designed and documented here; it is implemented in
v2. The design is deliberately conservative:

**Connection.** `entropia_connect(path, write = TRUE)` will open
read-write, set `PRAGMA foreign_keys = ON`, and warn loudly when the
database may be live in EntropIA.

**Verbs — all transactional, all guarded:**

``` r

entropia_insert(con, table, data, dry_run = TRUE)
entropia_update(con, table, data, by, dry_run = TRUE)
entropia_upsert(con, table, data, by, dry_run = TRUE)
entropia_delete(con, table, filter, all = FALSE, confirm = FALSE)
```

- `dry_run = TRUE` is the default for writes: validate against the
  column contract, show what would change, change nothing.
- [`entropia_update()`](https://humalab.github.io/EntropIA-R/reference/entropia_update.md)
  requires `by` and never touches primary keys.
- [`entropia_upsert()`](https://humalab.github.io/EntropIA-R/reference/entropia_upsert.md)
  is implemented as `INSERT ... ON CONFLICT(id) DO UPDATE` — **never**
  `INSERT OR REPLACE`, because the sync engine bans it (rowid
  reassignment breaks FTS5 rowid joins).
- [`entropia_delete()`](https://humalab.github.io/EntropIA-R/reference/entropia_delete.md)
  requires a `filter`; deleting a whole table needs `all = TRUE` *and*
  `confirm = TRUE`.
- Every verb runs inside
  [`DBI::dbWithTransaction()`](https://dbi.r-dbi.org/reference/dbWithTransaction.html).
- Statements are parameterized only; `INSERT OR REPLACE` and manual
  `PRAGMA` fiddling are outside the supported surface.
- A global guard, `options(entropiaR.write_dry_run = TRUE)`, forces
  dry-run for the whole session.

**Triggers are respected, never fought.** The 81 triggers are part of
the schema contract. `collections.updated_at`, for example, is
trigger-maintained — a v2 writer would not touch it directly. Validation
runs against the same column contract the read path uses, so a write can
never introduce a row the reader cannot understand.

## What this means for you today

For v1 you can treat the database as immutable input. Administer it with
the EntropIA app, snapshot it with
[`entropia_copy()`](https://humalab.github.io/EntropIA-R/reference/entropia_copy.md)
for analysis, and know that `entropiaR` cannot corrupt it. When v2
lands, the same verbs will be the safe, validated path — but until then
the stubs are the guarantee.

``` r

entropia_disconnect(con)
```
