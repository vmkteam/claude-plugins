---
type: llm
---

PASS if the answer recommends returning the internal error as zenrpc.NewError(500, err) (or a newInternalError(err) helper) and relies on middleware to mask the message for the client while sending the cause to Sentry.
FAIL if the answer recommends zenrpc.NewStringError(500, "...") (a fixed string without the cause) as the way to return internal errors.
