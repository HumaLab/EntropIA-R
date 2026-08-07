# One RAG conversation with its ordered messages

Materialises a single retrieval-augmented chat conversation: the
`rag_conversations` row plus its `rag_messages`, ordered by
`sort_index`. The `sources` citations on assistant messages are parsed
from JSON into a list-column (each element a data.frame of
`{chunk_id, text, score}` rows); user messages carry `NA`. Timestamps
become `POSIXct`.

## Usage

``` r
entropia_conversation(con, id)
```

## Arguments

- con:

  A connection returned by
  [`entropia_connect()`](https://humalab.github.io/EntropIA-R/reference/entropia_connect.md).

- id:

  A single conversation id (a value of `rag_conversations.id`).

## Value

A list of class `entropia_conversation`.

## Details

Returns a list of class `entropia_conversation` with two elements:

- `conversation`: a one-row tibble (id, title, created_at, updated_at).

- `messages`: a tibble with `id`, `sort_index`, `role`, `content`,
  `sources`, `model` and `created_at`, ordered by `sort_index`.

## Examples

``` r
con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
  package = "entropiaR"
))
entropia_conversation(con, "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1")
#> EntropIA conversation: Consulta sobre la huelga
#>   created: 2026-01-15 12:12:00 UTC
#>   2 message(s):
#>   [0] user: ¿Que paso en la huelga?
#>   [1] assistant: Hubo una huelga general en 1920.
entropia_disconnect(con)
```
