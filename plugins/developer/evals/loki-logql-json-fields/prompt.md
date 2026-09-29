---
description: Справочный скилл /loki — level и method в appkit-логах это JSON-поля, а не stream labels.
tags: [reference]
max_turns: 8
allowed_tools: [Read, Skill]
---

Нужна готовая команда pcurl: вытащить из Loki все ошибки RPC-метода orders.create сервиса ordersrv за последний час. Loki подключён через Grafana grafana.example.com (pcurl-профиль @grafana), uid Loki-датасорса — loki-main. Логи сервиса — стандартные JSON-логи appkit.
