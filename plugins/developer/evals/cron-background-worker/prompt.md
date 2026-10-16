---
description: >
  Триггер /cron по словам «фоновый воркер»: задача — метод менеджера домена, расписание —
  newCron() в pkg/app/cron.go с CronConfig, а не пакет <domain>/cron или горутина с тикером.
tags: [trigger, reference]
max_turns: 8
allowed_tools: [Read, Skill]
---

Go-сервис на vmkteam-стеке: pkg/app, pkg/db (mfd), домен pkg/tasks с TaskManager. Нужен фоновый воркер, который раз в 5 минут закрывает задачи с истёкшим дедлайном. Где и как его сделать? Покажи код.
