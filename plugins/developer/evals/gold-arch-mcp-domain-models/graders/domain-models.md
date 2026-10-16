---
type: llm
---

PASS if the answer says the domain must return its own models that embed the db models (e.g. `type Order struct{ db.Order }` with `NewOrder(*db.Order) *Order`) instead of []db.Order, and the MCP layer works only with domain models through its own models/converters, without importing pkg/db.
FAIL if MCP tools are allowed to use db.Order directly, or OrderManager.List keeps returning []db.Order as the recommended design.
