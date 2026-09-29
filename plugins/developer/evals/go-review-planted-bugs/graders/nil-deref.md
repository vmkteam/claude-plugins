---
type: llm
---

PASS if the review reports a possible nil pointer dereference in GetByID / NewOrder: either OrderByID returning nil for a missing order that is then passed to NewOrder, or `in.Address.City` when Address is nil. Either one is enough.
FAIL if the review mentions neither nil case.
