---
type: llm
---

The task has three acceptance criteria: search returns only the current user's orders; an order by ID is available only to its owner; a status change is persisted and a failed save returns an error to the client.
PASS if the review checks the criteria one by one and marks as not met at least these two: "order by ID only for its owner" (GetByID has no ownership check) and "failed save returns an error" (SetStatus ignores the UpdateOrder error).
FAIL if the review does not check the criteria individually, or marks either of these two as met.
