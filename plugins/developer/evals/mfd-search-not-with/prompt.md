---
description: >
  Справочник /mfd: условия IN и IS NULL по колонке — поля Search (ARRAY, NULL) в <ns>.xml и
  make mfd-model, а не search.With; пустой список статусов проверяется до запроса.
tags: [trigger, reference]
max_turns: 8
allowed_tools: [Read, Skill]
---

Go-сервис на vmkteam-стеке, pkg/db сгенерирован mfd-generator. В домене пишу выборку задач проекта со статусами из списка и не в архиве:

```go
search := &db.TaskSearch{ProjectID: &projectID}
search.With(`"t"."statusId" IN (?)`, pg.In(statusIDs))
search.With(`"t"."archivedAt" IS NULL`)
tasks, err := m.repo.TasksByFilters(ctx, search, db.PagerNoLimit)
```

Так нормально? Если нет — как правильно?
