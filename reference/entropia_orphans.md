# Detect orphaned rows (broken conceptual foreign keys)

EntropIA declares most relationships only conceptually (many have no
physical foreign-key constraint), so a row can silently point at a
parent that does not exist. `entropia_orphans()` scans every conceptual
foreign key in the schema and reports one row per broken reference:

## Usage

``` r
entropia_orphans(con)
```

## Arguments

- con:

  A connection returned by
  [`entropia_connect()`](https://humalab.github.io/EntropIA-R/reference/entropia_connect.md).

## Value

A tibble of class `entropia_orphans` with columns `kind`, `table`, `id`,
`column`, `ref_table` and `message`, ordered by `kind` then `id`.

## Details

- `items.collection_id` -\> `collections.id`

- `assets.item_id` -\> `items.id` and `assets.parent_asset_id` -\>
  `assets.id`

- `extractions`/`transcriptions`/`layouts`.`asset_id` -\> `assets.id`

- `entities.item_id` -\> `items.id` (and `asset_id` -\> `assets.id` when
  set)

- `triples.item_id` -\> `items.id` (and `asset_id` -\> `assets.id` when
  set)

- `notes.item_id` -\> `items.id` (and `asset_id` -\> `assets.id` when
  set)

- `annotations.asset_id` -\> `assets.id`

- `llm_results.target_id` -\> the table named by `target_type`
  (`asset`/`item`/`collection`; `unknown` and NULL targets are not
  checkable)

- `rag_messages.conversation_id` -\> `rag_conversations.id`

- `rag_chunks.item_id`/`asset_id` -\> `items.id`/`assets.id`

- `item_topics.item_id`/`topic_id` -\> `items.id`/`topics.id`

NULL foreign keys are never reported: they are the documented
"item-level" value for the optional `asset_id` columns, and the required
FKs are `NOT NULL` in the schema. Tables absent from the database are
skipped, so minimal and legacy schemas degrade gracefully. The result is
materialised (it is a small diagnostic, like
[`entropia_validate()`](https://humalab.github.io/EntropIA-R/reference/entropia_validate.md)
findings) and carries the `entropia_orphans` class.

## Examples

``` r
con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
  package = "entropiaR"
))
entropia_orphans(con) # zero findings on the example database
#> No orphaned rows detected.
entropia_disconnect(con)
```
