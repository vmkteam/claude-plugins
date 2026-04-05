---
name: youtrack
description: "YouTrack — работа с задачами через REST API и pcurl. Поиск, создание, обновление issues."
---

# YouTrack — работа с задачами

Работа с YouTrack через REST API. Для доступа используй `pcurl @{profile}`, где `{profile}` — pcurl-профиль YouTrack-инстанса проекта (определяется при онбординге или из CLAUDE.md проекта).

## Подключение

```
Profile: @{yt_profile}
Base URL: https://{yt_host}/api
```

Проверка доступа:
```bash
pcurl @{yt_profile} 'https://{yt_host}/api/admin/projects?fields=id,shortName,name&$top=50' -s
```

## Команды pcurl

### Поиск issues

```bash
# Все открытые issues проекта
pcurl @{profile} 'https://{host}/api/issues?query=project:{PROJECT}+state:Open&fields=idReadable,summary,created,updated,resolved,reporter(login),assignee(login)&$top=20&$orderBy=-created' -s

# По тексту
pcurl @{profile} 'https://{host}/api/issues?query=project:{PROJECT}+{search_text}&fields=idReadable,summary,created,updated,resolved&$top=20&$orderBy=-created' -s

# По нескольким проектам
pcurl @{profile} 'https://{host}/api/issues?query=project:{P1},{P2}+state:Open&fields=idReadable,summary,created,updated&$top=20&$orderBy=-created' -s

# Assigned to me
pcurl @{profile} 'https://{host}/api/issues?query=for:me+state:Open&fields=idReadable,summary,created,updated&$top=20' -s
```

### Детали issue

```bash
# Полная информация
pcurl @{profile} 'https://{host}/api/issues/{idReadable}?fields=idReadable,summary,description,created,updated,resolved,reporter(login,name),assignee(login,name),tags(name),comments(author(login),text,created)' -s

# Комментарии
pcurl @{profile} 'https://{host}/api/issues/{idReadable}/comments?fields=author(login,name),text,created&$top=50' -s
```

### Создание issue

```bash
pcurl @{profile} 'https://{host}/api/issues' -s -X POST \
  -H 'Content-Type: application/json' \
  -d '{"project":{"id":"{project_id}"},"summary":"{title}","description":"{description}"}'
```

> Для создания нужен project.id (не shortName):
> `pcurl @{profile} 'https://{host}/api/admin/projects?fields=id,shortName' -s`

### Добавить комментарий

```bash
pcurl @{profile} 'https://{host}/api/issues/{idReadable}/comments' -s -X POST \
  -H 'Content-Type: application/json' \
  -d '{"text":"{comment_text}"}'
```

### Обновить issue

```bash
pcurl @{profile} 'https://{host}/api/issues/{idReadable}' -s -X POST \
  -H 'Content-Type: application/json' \
  -d '{"summary":"{new_title}","description":"{new_description}"}'
```

## Query syntax

> **ВАЖНО:** Поле статуса может называться по-разному: `state`, `Stage`, `Status`. Реальное имя и значения определяются при `/onboard` и хранятся в `project-index.md` (state_field, state_open, state_done).

| Фильтр | Пример |
|---------|--------|
| Проект | `project:WEB`, `project:WEB,MSH` |
| Статус | `state:Open`, `state:Resolved` (или `Stage:Backlog` — зависит от проекта) |
| Assigned | `for:me`, `for:{login}` |
| Текст | просто слова в query |
| Дата | `created:Today`, `created:2026-04-01..Today` |
| Тег | `tag:{tag_name}` |
| Приоритет | `priority:Critical`, `priority:Normal` |
| Сортировка | `sort by:created desc` |

## Аттачи

```bash
# Список аттачей issue
pcurl @{profile} 'https://{host}/api/issues/{idReadable}/attachments?fields=id,name,url,mimeType,size,created,author(login)' -s

# Скачать аттач (url из поля выше)
pcurl @{profile} 'https://{host}{url}' -s -o docs/llm/tasks/{TASK_ID}/{filename}
```

Поддерживаемые типы для анализа:
- **Изображения** (image/png, image/jpeg, image/gif, image/webp) — скриншоты багов, макеты UI
- **PDF** (application/pdf) — ТЗ, спецификации
- Остальные форматы — упомянуть в research.md без скачивания

## Прямые ссылки

```
https://{host}/issue/{idReadable}
https://{host}/issues?q=project:{shortName}
```
