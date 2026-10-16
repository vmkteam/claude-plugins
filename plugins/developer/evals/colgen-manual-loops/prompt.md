---
description: >
  Триггер /colgen по словам «ручные циклы»: сбор id, map по id и конвертация списка —
  директивы colgen в collection.go домена, а не новые циклы или свои дженерики.
tags: [trigger, reference]
max_turns: 8
allowed_tools: [Read, Skill]
---

Метод домена в Go-сервисе на vmkteam-стеке (pkg/db сгенерирован mfd, домен — pkg/shop, модели домена встраивают db: `type Order struct{ db.Order; Product *Product }`). Тут много ручных циклов — перепиши аккуратнее:

```go
func (m *OrderManager) UserOrders(ctx context.Context, userID int) ([]Order, error) {
	list, err := m.repo.OrdersByFilters(ctx, &db.OrderSearch{UserID: &userID}, db.PagerNoLimit)
	if err != nil {
		return nil, err
	}

	seen := map[int]bool{}
	var productIDs []int
	for _, o := range list {
		if !seen[o.ProductID] {
			seen[o.ProductID] = true
			productIDs = append(productIDs, o.ProductID)
		}
	}

	products, err := m.repo.ProductsByFilters(ctx, &db.ProductSearch{IDs: productIDs}, db.PagerNoLimit)
	if err != nil {
		return nil, err
	}
	byID := map[int]db.Product{}
	for _, p := range products {
		byID[p.ID] = p
	}

	res := make([]Order, 0, len(list))
	for _, o := range list {
		ord := Order{Order: o}
		if p, ok := byID[o.ProductID]; ok {
			ord.Product = &Product{Product: p}
		}
		res = append(res, ord)
	}
	return res, nil
}
```
