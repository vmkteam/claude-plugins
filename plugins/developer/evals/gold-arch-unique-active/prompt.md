---
description: >
  Справочник /gold-arch: «уникален среди активных» — частичный UNIQUE-индекс в схеме,
  а не ручной COUNT в db-слое.
tags: [reference]
max_turns: 8
allowed_tools: [Read, Skill]
---

У нас Go-сервис на vmkteam-стеке (go-pg, mfd, pgDesigner). Нужно, чтобы code проекта был уникален среди активных проектов; удалённые (statusId = 3) не в счёт. Где и как это правильно реализовать?
