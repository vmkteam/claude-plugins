---
description: >
  Справочник /security (и /zenrpc): внутренняя ошибка — newInternalError(err) через zm.WithErrorSLog,
  клиенту «Internal error», причина — в Sentry; NewStringError(500) для этого не годится.
tags: [reference]
max_turns: 8
allowed_tools: [Read, Skill]
---

В RPC-методе на zenrpc упал запрос в БД. Как вернуть ошибку, чтобы клиент не увидел текст ошибки Postgres, а причина попала в Sentry? Покажи код.
