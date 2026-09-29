---
type: regex
target: { source: file, path: docs/shop.pgd }
pattern: '<table\b(?:(?!</table>)[\s\S])*<index\b'
match: not_contains
---
