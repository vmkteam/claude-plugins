---
type: llm
---

PASS if the main recommendation is a partial unique index in the schema (optionally with handling of the unique violation in the domain or API layer).
FAIL if the main recommendation is a hand-written COUNT/SELECT existence check in the db layer or application code as the way to enforce uniqueness.
