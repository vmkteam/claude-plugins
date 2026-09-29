---
max_turns: 20
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit]
---

Напиши тесты на ProjectService.Archive из pkg/rpc по сценариям из spec задачи. Файл — pkg/rpc/project_archive_test.go.

```gherkin
Scenario: владелец архивирует активный проект
  Given активный проект пользователя 10
  When пользователь 10 вызывает project.Archive
  Then статус проекта — Archived

Scenario Outline: неактивный проект архивировать нельзя
  Given проект пользователя 10 в статусе <status>
  When пользователь 10 вызывает project.Archive
  Then ошибка ErrInvalidStatus
  Examples:
    | status   |
    | Archived |
    | Deleted  |

Scenario: чужой проект архивировать нельзя
  Given активный проект пользователя 10
  When пользователь 20 вызывает project.Archive
  Then ошибка ErrNotFound, статус проекта остаётся Active
```
