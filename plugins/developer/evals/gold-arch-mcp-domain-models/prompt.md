---
description: >
  Триггер /gold-arch по словам «MCP-сервер»: pkg/mcp, домен отдаёт свои модели (embed db),
  MCP-слой не импортирует pkg/db и конвертирует модели домена в свои.
tags: [trigger, reference]
max_turns: 8
allowed_tools: [Read, Skill]
---

Go-сервис на vmkteam-стеке: pkg/db сгенерирован mfd, домен pkg/orders с OrderManager, JSON-RPC в pkg/rpc. Добавляем MCP-сервер на vmkteam/mcpkit с tools «список заказов» и «отменить заказ». Сейчас OrderManager.List возвращает []db.Order. Как разложить код и какие модели отдавать из домена в MCP?
