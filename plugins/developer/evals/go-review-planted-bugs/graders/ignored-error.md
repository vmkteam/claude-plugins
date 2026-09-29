---
type: llm
---

PASS if the review reports that SetStatus ignores the error returned by UpdateOrder (`ok, _ := ...`), so a failed update is not reported to the client.
FAIL if the review does not mention the ignored UpdateOrder error.
