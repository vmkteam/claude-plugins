---
type: regex
target: { source: file, path: docs/shop.pgd }
pattern: '<index\b[^>]*name="idx_users_search_tsv"[^>]*using="gin"|<index\b[^>]*using="gin"[^>]*name="idx_users_search_tsv"'
flags: i
---
