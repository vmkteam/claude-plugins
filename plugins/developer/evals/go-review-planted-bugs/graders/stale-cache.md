---
type: llm
---

PASS if the review reports that SetStatus changes the order in the database without updating or invalidating the `cache` map, so GetByID can keep returning a stale status (or otherwise flags that the cache has no invalidation).
FAIL if the review does not mention cache staleness / missing invalidation.
