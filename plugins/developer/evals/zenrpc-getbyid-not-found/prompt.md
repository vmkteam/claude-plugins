---
description: >
  Справочник /zenrpc: EntityByID возвращает (nil, nil), если записи нет — метод обязан вернуть
  ErrNotFound; аннотации //zenrpc: и make generate.
tags: [reference]
max_turns: 8
allowed_tools: [Read, Skill]
---

Напиши zenrpc-метод ProjectService.GetByID для pkg/rpc. Есть репозиторий `repo.ProjectByID(ctx, id int) (*db.Project, error)` (сгенерирован mfd) и конвертер `NewProject(*db.Project) *Project`.
