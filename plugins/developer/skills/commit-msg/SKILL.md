---
name: commit-msg
description: "Commit message — краткое сообщение коммита на английском из git diff. Используй перед `git commit`, после /solve, или при явной просьбе 'сгенерируй commit message'."
effort: low
---

Generate a concise commit message in English from all current changes: staged, unstaged, and new files.

0. Format and lint first, only when the project supports it: if `make -n fmt lint >/dev/null 2>&1` succeeds (a Makefile with both targets exists), run `make fmt lint` — formatting can change files, so read the diff after it. No Makefile or no such targets — skip with one line saying so. Skip it too if fmt and lint already passed after the last code change (for example, /solve just ran them). If lint fails, don't fix the code in this step and don't stop: write the message anyway and list the lint errors after it.
1. Run `git diff --cached`, `git diff` and `git status --short`. Untracked files don't appear in diffs — read new files that will be committed. If only part of the changes is staged, say which files are not staged.
2. Subject line: the ticket ID from the branch name (if present), a space, then the summary: `PLF-852 Add ...`. The summary is at most 50 characters, not counting the ticket prefix; the whole line never exceeds 72. Capitalized, no period at the end, imperative mood ("Add", "Fix", "Remove" — not "Added", "Fixed").
3. If the summary doesn't fit, keep the main change in the subject and move the rest to the body.
4. Separate subject from body with a blank line.
5. Body: bullet points on what changed and why (not how), wrapped at 72 chars. Group related changes, mention bug fixes with "Fix".
6. Output only the commit message, plus the lint errors from step 0 if there were any.

Style follows https://cbea.ms/git-commit/.

Example:
```
PLF-819 Add user validation for order creation

- Add email format and phone length validation in pkg/vt/order.go
- Fix missing nil check for optional DeliveryAddress field
- Update OrderSearch with new CreatedAtFrom/CreatedAtTo filters
- Regenerate zenrpc and mfd-model after schema changes
```
