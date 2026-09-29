---
type: llm
---

PASS if the review reports that GetByID returns an order without checking that it belongs to the current user (missing ownership/authorization check, IDOR), as a finding that needs fixing.
FAIL if the review does not mention the missing ownership check in GetByID.
