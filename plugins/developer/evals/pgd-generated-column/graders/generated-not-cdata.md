---
type: regex
target: { source: file, path: docs/shop.pgd }
pattern: '<generated\b[^>]*>\s*<!\[CDATA\['
match: not_contains
---
