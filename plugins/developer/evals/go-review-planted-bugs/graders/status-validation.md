---
type: llm
---

PASS if the review reports that SetStatus accepts any statusId without validating it (no check of allowed statuses or status transitions).
FAIL if the review does not mention the missing statusId validation.
