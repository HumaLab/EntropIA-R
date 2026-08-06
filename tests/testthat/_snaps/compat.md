# schema warnings and errors have stable actionable messages

    Code
      conditionMessage(w)
    Output
      [1] "Database schema version \"0030_future_schema\" is newer than the latest entropiaR understands (\"0029_rag_chunks\").\ni Read-only access continues, but new columns may not be typed.\ni Set `options(entropiaR.schema_policy = 'allow')` to silence this."

---

    Code
      conditionMessage(err)
    Output
      [1] "Schema compatibility check failed.\nCaused by error:\n! Database at schema version \"0001_initial\" is missing required column(s): items.title.\ni The database does not satisfy the entropiaR column contract.\ni If it is a valid EntropIA database, update entropiaR; otherwise the file may be partial or corrupt. To proceed anyway, set `options(entropiaR.schema_policy = 'allow')`."

