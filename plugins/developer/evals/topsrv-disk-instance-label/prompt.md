---
description: Справочный скилл /topsrv — хост в PromQL это лейбл instance, заполненность диска считается из topsrv_filesystem_bytes, range-запрос — metric.queryRange с unix-секундами.
tags: [reference]
max_turns: 8
allowed_tools: [Read, Skill]
---

Нужны готовые команды pcurl к topsrv: текущая заполненность файловых систем в процентах и load average за последние 6 часов на сервере db-2. Проект в topsrv — shop, pcurl-профиль @topsrv-shop.
