---
type: llm
---

PASS if the answer warns that an empty statusIDs list must be handled before the query (early return), because the generated ARRAY filter is skipped for an empty slice and the query would return all tasks of the project (or `IN ()` with pg.In of an empty list is a syntax error).
FAIL if empty statusIDs is not mentioned or the answer claims an empty slice simply returns no rows.
