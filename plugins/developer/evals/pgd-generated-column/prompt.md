---
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill, Edit]
---

В docs/shop.pgd добавь в users хранимую колонку search_tsv типа tsvector, которая считается из name (to_tsvector по-русски), и GIN-индекс idx_users_search_tsv по ней.
