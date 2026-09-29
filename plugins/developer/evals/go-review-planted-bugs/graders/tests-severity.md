---
type: llm
---

The package already has a test harness (pkg/rpc/rpc_test.go with TestMain), so missing tests for new reachable functionality should be major.
PASS if missing tests for the new methods are reported with severity major or blocker.
FAIL if they are labeled minor or nit, or not reported.
