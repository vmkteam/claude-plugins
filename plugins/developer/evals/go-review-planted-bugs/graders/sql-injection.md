---
type: llm
---

PASS if the review reports that SearchByTitle (pkg/db/order_repo_ext.go) builds raw SQL by concatenating the user-supplied `title` into the query string, i.e. an SQL injection, as a finding that needs fixing.
FAIL if the review does not mention this SQL injection, or mentions it only as acceptable.
