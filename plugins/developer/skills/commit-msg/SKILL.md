---
name: commit-msg
description: "Commit message — краткое сообщение коммита на английском из git diff. Используй перед `git commit`, после /solve, или при явной просьбе 'сгенерируй commit message'."
---

Generate a concise commit message in English based on the full `git diff` (both staged and unstaged changes).

Pre-commit:
1. Run `make fmt lint` before analyzing the diff. If it produces changes or errors, fix them first.

Rules (based on https://cbea.ms/git-commit/):
1. Run `git diff` and `git diff --cached` to see all changes
2. Subject line: max 50 chars, capitalize, no period at end
3. Use imperative mood ("Add", "Fix", "Remove", not "Added", "Fixed")
4. Add ticket prefix from branch name if present (e.g. PLF-852)
5. Separate subject from body with a blank line
6. Body: bullet points summarizing what and why (not how), wrap at 72 chars
7. Group related changes together, mention bug fixes with "Fix"
8. Output only the commit message, nothing else

Example:
```
PLF-819 Add user validation for order creation

- Add email format and phone length validation in pkg/vt/order.go
- Fix missing nil check for optional DeliveryAddress field
- Update OrderSearch with new CreatedAtFrom/CreatedAtTo filters
- Regenerate zenrpc and mfd-model after schema changes
```
