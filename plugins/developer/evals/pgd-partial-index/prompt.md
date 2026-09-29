---
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill, Edit]
---

В docs/shop.pgd добавь частичный индекс idx_users_lower_email по lower(email) только для неудалённых пользователей (deleted_at IS NULL).
