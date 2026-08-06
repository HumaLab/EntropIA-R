# key messages have stable snapshots

    Code
      conditionMessage(w)
    Output
      [1] "Malformed JSON, returning NA: parse error: premature EOF {\"unclosed\": (right here) ------^"

---

    Code
      conditionMessage(w2)
    Output
      [1] "Malformed JSON in items.metadata, returning NA: parse error: premature EOF {\"bad\": (right here) ------^"

---

    Code
      conditionMessage(err)
    Output
      [1] "`entropia_insert()` is not available in entropiaR v1.\ni v1 is read-only: the database may be live in EntropIA (WAL) and is protected by 81 sync/activity triggers.\ni Write support ships in v2, where you open the database for writing with `entropia_connect()` (`path`, `write = TRUE`).\ni The v2 write design is documented in 'vignettes/administration.Rmd'."

