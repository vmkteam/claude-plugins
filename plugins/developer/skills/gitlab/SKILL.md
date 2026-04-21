---
name: gitlab
description: "GitLab — работа с MR, pipelines, discussions через REST API v4 и pcurl. Используй для поиска/создания/обновления MR, чтения пайплайнов, публикации threads или комментариев в MR."
---

# GitLab — работа с MR, pipelines, code review

Работа с self-hosted GitLab через REST API v4. Для доступа используй `pcurl @{gl_profile}`, где `{gl_profile}` — pcurl-профиль GitLab-инстанса (определяется при онбординге).

## Подключение

```
Profile: @{gl_profile}
Base URL: https://{gl_host}/api/v4
Project ID: {gl_project_id}
```

Проверка доступа:
```bash
pcurl @{gl_profile} 'https://{gl_host}/api/v4/projects/{gl_project_id}?simple=true' -s
```

## Merge Requests

### Список MR

```bash
# Открытые MR проекта
pcurl @{gl_profile} 'https://{gl_host}/api/v4/projects/{gl_project_id}/merge_requests?state=opened&order_by=updated_at&per_page=20' -s

# Мои MR
pcurl @{gl_profile} 'https://{gl_host}/api/v4/projects/{gl_project_id}/merge_requests?state=opened&scope=created_by_me' -s

# MR на мой review
pcurl @{gl_profile} 'https://{gl_host}/api/v4/projects/{gl_project_id}/merge_requests?state=opened&reviewer_username={username}' -s

# MR по ветке
pcurl @{gl_profile} 'https://{gl_host}/api/v4/projects/{gl_project_id}/merge_requests?state=opened&source_branch={branch}' -s
```

### Детали MR

```bash
# Полная информация
pcurl @{gl_profile} 'https://{gl_host}/api/v4/projects/{gl_project_id}/merge_requests/{mr_iid}' -s

# Diff (изменения)
pcurl @{gl_profile} 'https://{gl_host}/api/v4/projects/{gl_project_id}/merge_requests/{mr_iid}/changes' -s

# Список коммитов в MR
pcurl @{gl_profile} 'https://{gl_host}/api/v4/projects/{gl_project_id}/merge_requests/{mr_iid}/commits' -s
```

### Approve / Unapprove MR

```bash
# Approve
pcurl @{gl_profile} 'https://{gl_host}/api/v4/projects/{gl_project_id}/merge_requests/{mr_iid}/approve' -s -X POST

# Unapprove
pcurl @{gl_profile} 'https://{gl_host}/api/v4/projects/{gl_project_id}/merge_requests/{mr_iid}/unapprove' -s -X POST
```

## Discussions (треды в MR)

### Прочитать все треды

```bash
pcurl @{gl_profile} 'https://{gl_host}/api/v4/projects/{gl_project_id}/merge_requests/{mr_iid}/discussions?per_page=100' -s
```

### Создать новый тред (inline comment на строку кода)

```bash
pcurl @{gl_profile} 'https://{gl_host}/api/v4/projects/{gl_project_id}/merge_requests/{mr_iid}/discussions' -s -X POST \
  -H 'Content-Type: application/json' \
  -d '{
    "body": "{comment_text}",
    "position": {
      "base_sha": "{base_sha}",
      "start_sha": "{start_sha}",
      "head_sha": "{head_sha}",
      "position_type": "text",
      "old_path": "{file_path}",
      "new_path": "{file_path}",
      "new_line": {line_number}
    }
  }'
```

> `base_sha`, `start_sha`, `head_sha` берутся из `diff_refs` в деталях MR.

### Создать общий тред (не привязанный к строке)

```bash
pcurl @{gl_profile} 'https://{gl_host}/api/v4/projects/{gl_project_id}/merge_requests/{mr_iid}/discussions' -s -X POST \
  -H 'Content-Type: application/json' \
  -d '{"body": "{comment_text}"}'
```

### Ответить в существующий тред

```bash
pcurl @{gl_profile} 'https://{gl_host}/api/v4/projects/{gl_project_id}/merge_requests/{mr_iid}/discussions/{discussion_id}/notes' -s -X POST \
  -H 'Content-Type: application/json' \
  -d '{"body": "{reply_text}"}'
```

### Resolve / Unresolve тред

```bash
pcurl @{gl_profile} 'https://{gl_host}/api/v4/projects/{gl_project_id}/merge_requests/{mr_iid}/discussions/{discussion_id}' -s -X PUT \
  -H 'Content-Type: application/json' \
  -d '{"resolved": true}'
```

## Pipelines

### Список pipelines MR

```bash
pcurl @{gl_profile} 'https://{gl_host}/api/v4/projects/{gl_project_id}/merge_requests/{mr_iid}/pipelines' -s
```

### Последний pipeline ветки

```bash
pcurl @{gl_profile} 'https://{gl_host}/api/v4/projects/{gl_project_id}/pipelines?ref={branch}&per_page=1&order_by=id&sort=desc' -s
```

### Детали pipeline

```bash
pcurl @{gl_profile} 'https://{gl_host}/api/v4/projects/{gl_project_id}/pipelines/{pipeline_id}' -s
```

### Jobs pipeline (включая статусы)

```bash
pcurl @{gl_profile} 'https://{gl_host}/api/v4/projects/{gl_project_id}/pipelines/{pipeline_id}/jobs?per_page=50' -s
```

### Лог упавшего job

```bash
pcurl @{gl_profile} 'https://{gl_host}/api/v4/projects/{gl_project_id}/jobs/{job_id}/trace' -s
```

> Лог возвращается plain text. Ищи ошибки ближе к концу вывода.

### Retry упавшего pipeline / job

```bash
# Retry весь pipeline
pcurl @{gl_profile} 'https://{gl_host}/api/v4/projects/{gl_project_id}/pipelines/{pipeline_id}/retry' -s -X POST

# Retry конкретный job
pcurl @{gl_profile} 'https://{gl_host}/api/v4/projects/{gl_project_id}/jobs/{job_id}/retry' -s -X POST
```

## Review MR через /go-review

Для ревью MR:
1. Получить diff MR (endpoint `/changes`)
2. Прочитать затронутые файлы локально (checkout ветки или через API)
3. Запустить `/go-review` на изменения
4. Результаты ревью — создать треды в MR (inline comments на конкретные строки)

```bash
# Получить diff и diff_refs
pcurl @{gl_profile} 'https://{gl_host}/api/v4/projects/{gl_project_id}/merge_requests/{mr_iid}/changes' -s

# Для каждого замечания — создать inline тред (см. секцию Discussions)
```

## Полезные фильтры

| Параметр | Значения |
|----------|----------|
| `state` | `opened`, `closed`, `merged`, `all` |
| `scope` | `created_by_me`, `assigned_to_me`, `all` |
| `order_by` | `created_at`, `updated_at` |
| `sort` | `asc`, `desc` |
| `per_page` | 1-100 (default 20) |

## Прямые ссылки

```
https://{gl_host}/{gl_project_path}/-/merge_requests/{mr_iid}
https://{gl_host}/{gl_project_path}/-/pipelines/{pipeline_id}
https://{gl_host}/{gl_project_path}/-/jobs/{job_id}
```
