---
max_turns: 20
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit]
---

Напиши тесты на ProjectService.Archive из pkg/vt по сценариям из spec задачи. Файл — pkg/vt/project_archive_test.go.

```gherkin
Scenario: активный проект архивируется
  Given активный проект
  When администратор вызывает project.Archive
  Then статус проекта — Archived

Scenario Outline: неактивный проект архивировать нельзя
  Given проект в статусе <status>
  When администратор вызывает project.Archive
  Then ошибка ErrInvalidStatus
  Examples:
    | status   |
    | Archived |
    | Deleted  |
```
