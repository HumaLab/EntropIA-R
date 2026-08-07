# Document lengths (chars/words per row)

**\[experimental\]**

## Usage

``` r
entropia_document_lengths(x, text_var = "text")
```

## Arguments

- x:

  A data frame or tibble of collected rows.

- text_var:

  Column holding the document text, selected by name or bare
  (tidyselect). Default `"text"`.

## Value

`x` with two appended columns: `n_chars` (characters) and `n_words`
(whitespace-separated tokens).

## Details

Appends character and word counts per row of a collected tibble. Each
row is treated as one document. `NA` text yields `NA` counts; empty or
whitespace-only text yields 0 chars and 0 words. Words are
whitespace-separated tokens (multiple spaces collapse; punctuation stays
attached to its token).

## Examples

``` r
con <- entropia_connect(system.file("extdata", "entropia-example.sqlite",
  package = "entropiaR"
))
text_layer <- entropia_collect(entropia_text(con))
entropia_document_lengths(text_layer)
#> # A tibble: 5 × 12
#>   id             item_id path  type   size created_at sort_index parent_asset_id
#>   <chr>          <chr>   <chr> <chr> <int>    <int64>      <int> <chr>          
#> 1 33333333-3333… 222222… stor… pdf   20480      1.e12          0 NA             
#> 2 33333333-3333… 222222… stor… pdf   10240      1.e12          1 33333333-3333-…
#> 3 33333333-3333… 222222… stor… pdf   10240      1.e12          2 33333333-3333-…
#> 4 33333333-3333… 222222… stor… image  5120      1.e12          0 NA             
#> 5 33333333-3333… 222222… stor… audio 40960      1.e12          0 NA             
#> # ℹ 4 more variables: page_number <int>, text <chr>, n_chars <int>,
#> #   n_words <int>
entropia_disconnect(con)
```
