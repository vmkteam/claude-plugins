---
name: sentry
description: "Sentry — мониторинг ошибок (issues, events, releases) через REST API. Используй когда нужно найти ошибку по ключевым словам, разобрать stack trace, проверить что релиз поднялся или сопоставить ошибку с коммитом."
---

# Sentry — мониторинг ошибок

Sentry (self-hosted или cloud) для мониторинга ошибок. Доступ через pcurl.

Конкретные хосты, org slug и профиль определяются при онбординге (`/onboard`) и хранятся в `.claude/memory/project-index.md`.

## Подключение

```
Profile: @{sentry_profile}
Base URL: https://{sentry_host}/api/0
Org slug: {org}
```

## Команды pcurl

### Список проектов
```bash
pcurl @{profile} 'https://{host}/api/0/organizations/{org}/projects/' -s
```

### Поиск issues
```bash
# За период, сортировка по частоте
pcurl @{profile} 'https://{host}/api/0/organizations/{org}/issues/?query=is:unresolved&sort=freq&statsPeriod={period}&limit=25' -s

# По проекту
pcurl @{profile} 'https://{host}/api/0/organizations/{org}/issues/?query=is:unresolved+project:{project_slug}&sort=freq&statsPeriod={period}' -s

# По endpoint/URL
pcurl @{profile} 'https://{host}/api/0/organizations/{org}/issues/?query=is:unresolved+url:{url_pattern}&sort=freq&statsPeriod={period}' -s

# По типу ошибки
pcurl @{profile} 'https://{host}/api/0/organizations/{org}/issues/?query=is:unresolved+error.type:{ErrorType}&statsPeriod={period}' -s

# Новые issues (first seen за период)
pcurl @{profile} 'https://{host}/api/0/organizations/{org}/issues/?query=is:unresolved+firstSeen:>-{period}&sort=date' -s
```

### Детали issue
```bash
pcurl @{profile} 'https://{host}/api/0/issues/{issue_id}/' -s
pcurl @{profile} 'https://{host}/api/0/issues/{issue_id}/events/latest/' -s
pcurl @{profile} 'https://{host}/api/0/issues/{issue_id}/tags/' -s
```

### Events (Discover)
```bash
pcurl @{profile} 'https://{host}/api/0/organizations/{org}/events/?query=event.type:error+transaction:{endpoint}&field=count()&field=title&statsPeriod={period}&sort=-count' -s
```

### Релизы
```bash
pcurl @{profile} 'https://{host}/api/0/projects/{org}/{project_slug}/releases/?per_page=5' -s
pcurl @{profile} 'https://{host}/api/0/organizations/{org}/releases/{version}/commits/' -s
```

## Query syntax

| Фильтр | Пример |
|---------|--------|
| Проект | `project:{slug}` |
| Статус | `is:unresolved`, `is:resolved`, `is:ignored` |
| Assigned | `assigned:me`, `assigned:{username}` |
| URL | `url:/rpc/*` |
| Тип ошибки | `error.type:TimeoutError` |
| Уровень | `level:error`, `level:fatal` |
| First seen | `firstSeen:-1h`, `firstSeen:+7d` |
| Times seen | `times_seen:>100` |
| Текст | `context deadline`, `invalid_grant` |

## Параметры

| Параметр | Значения |
|----------|----------|
| `sort` | `date`, `freq`, `new`, `priority` |
| `statsPeriod` | `1h`, `24h`, `7d`, `14d`, `30d` |
| `limit` | 1-100 (default 25) |

## Ключевые поля ответа

Issue: `id`, `shortId`, `title`, `count` (string!), `userCount`, `firstSeen`, `lastSeen`, `project.slug`, `metadata.type`, `level`, `status`.

Event: `entries` (stacktrace, breadcrumbs), `tags`, `context`, `dateCreated`.

## Прямые ссылки

```
https://{host}/organizations/{org}/issues/{issue_id}/
https://{host}/organizations/{org}/issues/?project={project_id}&query=is:unresolved&sort=freq&statsPeriod={period}
```
