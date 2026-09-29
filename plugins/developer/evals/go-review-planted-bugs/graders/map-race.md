---
type: llm
---

PASS if the review reports that the shared `cache` map in OrderService is read and written in GetByID without synchronization (data race / concurrent map writes under concurrent RPC calls), or otherwise flags the cache as unsafe for concurrent use.
FAIL if the review does not mention the unsynchronized cache map.
