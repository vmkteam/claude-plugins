---
name: incident
description: "Incident — реакция на production инцидент. Сбор данных, timeline, root cause, hotfix, post-mortem."
---

# Incident — реакция на production инцидент

Структурированный workflow для расследования и устранения production инцидента. Собирает данные из всех систем, строит timeline, находит root cause, координирует hotfix.

Подключения из `.claude/memory/project-index.md` и `~/.claude/memory/infra-{group}.md`.

## Использование

```
/incident "500 ошибки на /api/v1/orders"
/incident "не работает авторизация"
/incident PLF-900
```

Можно передать:
- Описание проблемы (свободный текст)
- ID задачи из YouTrack (если уже заведена)
- URL из Sentry / Grafana alert

## Flow

```
TRIAGE → GATHER → TIMELINE → ROOT CAUSE → ⏸ HITL → MITIGATE → ⏸ HITL → POSTMORTEM
```

---

### 1. TRIAGE — оценка масштаба

Быстрая оценка (параллельно, <2 минут):

```bash
# Sentry: всплеск ошибок за последний час
pcurl @{sentry_profile} 'https://{sentry_host}/api/0/organizations/{org}/issues/?query=is:unresolved+project:{sentry_slug}&sort=freq&statsPeriod=1h&limit=10' -s

# Prometheus: error rate и latency
pcurl @{prom_profile} 'https://{prom_host}/api/v1/query' -s -G \
  --data-urlencode 'query=rate(app_http_response_count_total{job="{job}",code=~"5.."}[5m])'

pcurl @{prom_profile} 'https://{prom_host}/api/v1/query' -s -G \
  --data-urlencode 'query=histogram_quantile(0.99, rate(app_http_response_time_seconds_bucket{job="{job}"}[5m]))'

# Nomad: статус аллокаций
pcurl @{nomad_profile} 'https://{nomad_host}/v1/job/{nomad_job}/allocations' -s

# API: up check (через Prometheus, /status недоступен снаружи)
pcurl @{prom_profile} 'https://{prom_host}/api/v1/query' -s -G \
  --data-urlencode 'query=up{job="{job}"}'
```

Определить severity:

| Severity | Критерии | Действия |
|----------|----------|----------|
| **P1 Critical** | Сервис недоступен, >50% запросов 5xx, потеря данных | Немедленный hotfix, оповещение |
| **P2 Major** | Деградация, >10% ошибок, часть функций недоступна | Hotfix в приоритете |
| **P3 Minor** | Единичные ошибки, не влияет на основной flow | Плановое исправление |

### 2. GATHER — сбор данных

Глубокий сбор по всем источникам (параллельно):

#### Sentry — ошибки и stacktrace
```bash
# Top issues за период инцидента
pcurl @{sentry_profile} 'https://{sentry_host}/api/0/organizations/{org}/issues/?query=is:unresolved+project:{sentry_slug}&sort=freq&statsPeriod=1h&limit=10' -s

# Детали топ issue (stacktrace, tags, affected users)
pcurl @{sentry_profile} 'https://{sentry_host}/api/0/issues/{issue_id}/events/latest/' -s

# Release и commit
pcurl @{sentry_profile} 'https://{sentry_host}/api/0/issues/{issue_id}/' -s
```

#### Prometheus — метрики
```bash
# Error rate за последние 2 часа (range query)
pcurl @{prom_profile} 'https://{prom_host}/api/v1/query_range' -s -G \
  --data-urlencode 'query=rate(app_http_response_count_total{job="{job}",code=~"5.."}[1m])' \
  --data-urlencode 'start={2h_ago_rfc3339}' \
  --data-urlencode 'end={now_rfc3339}' \
  --data-urlencode 'step=60'

# Latency p99
pcurl @{prom_profile} 'https://{prom_host}/api/v1/query_range' -s -G \
  --data-urlencode 'query=histogram_quantile(0.99, rate(app_http_response_time_seconds_bucket{job="{job}"}[1m]))' \
  --data-urlencode 'start={2h_ago_rfc3339}' \
  --data-urlencode 'end={now_rfc3339}' \
  --data-urlencode 'step=60'

# DB connections / goroutines / memory
pcurl @{prom_profile} 'https://{prom_host}/api/v1/query' -s -G \
  --data-urlencode 'query=app_db_open_connections{job="{job}"}'

pcurl @{prom_profile} 'https://{prom_host}/api/v1/query' -s -G \
  --data-urlencode 'query=go_goroutines{job="{job}"}'

pcurl @{prom_profile} 'https://{prom_host}/api/v1/query' -s -G \
  --data-urlencode 'query=go_memstats_alloc_bytes{job="{job}"}'
```

#### Loki — логи
```bash
# Ошибки за последний час (через Grafana proxy)
pcurl @{grafana_profile} 'https://{grafana_host}/api/datasources/uid/{loki_uid}/resources/query_range' -s -G \
  --data-urlencode 'query={service_name="{service_name}"} |= "error" | logfmt' \
  --data-urlencode 'start={1h_ago_ns}' \
  --data-urlencode 'end={now_ns}' \
  --data-urlencode 'limit=100'
```

#### Nomad — деплой и аллокации
```bash
# Последние деплои
pcurl @{nomad_profile} 'https://{nomad_host}/v1/job/{nomad_job}/deployments' -s

# Статус аллокаций (restarts, failed)
pcurl @{nomad_profile} 'https://{nomad_host}/v1/job/{nomad_job}/allocations' -s
```

#### Git — последние изменения
```bash
# Последние коммиты в production ветке
git log --oneline -20 origin/master

# Что менялось в последнем деплое
git diff HEAD~5..HEAD --stat
```

#### GitLab — последний pipeline
```bash
# Последний pipeline на master
pcurl @{gl_profile} 'https://{gl_host}/api/v4/projects/{gl_project_id}/pipelines?ref=master&per_page=3&order_by=id&sort=desc' -s
```

### 3. TIMELINE — построение хронологии

На основе собранных данных построить timeline:

```markdown
## Timeline

| Время (UTC) | Источник | Событие |
|-------------|----------|---------|
| {time} | GitLab | Pipeline #{id} завершён, deploy на production |
| {time} | Prometheus | Error rate вырос с 0.1% до 15% |
| {time} | Sentry | Первое появление {error_type} (issue #{id}) |
| {time} | Loki | Массовые ошибки "{message}" |
| {time} | — | Инцидент обнаружен |
```

Найти **trigger event** — что изменилось непосредственно перед началом ошибок:
- Деплой новой версии?
- Изменение конфигурации?
- Рост нагрузки?
- Падение зависимости (другой сервис, БД)?

### 4. ROOT CAUSE — определение причины

На основе timeline и данных определить:
- **Что сломалось** — конкретный компонент, метод, запрос
- **Почему сломалось** — причина (баг в коде, конфиг, инфра, зависимость)
- **Когда началось** — точное время и trigger
- **Масштаб** — сколько пользователей/запросов затронуто

Если причина в коде — найти конкретный коммит:
```bash
# Сравнить текущую версию с предыдущей
git log --oneline {prev_tag}..{current_tag}

# Blame на проблемный файл
git log --oneline -5 -- {file}
```

### ⏸ HITL: Утверждение диагноза

Показать пользователю:
- **Severity:** P1/P2/P3
- **Timeline** (таблица)
- **Root cause** (описание)
- **Trigger:** {что вызвало}
- **Impact:** {масштаб}

Предложить действие:
- **Hotfix** — исправить через `/solve` (создать задачу если нет)
- **Rollback** — откатить деплой (пользователь делает сам)
- **Config fix** — изменить конфигурацию
- **Wait** — проблема в зависимости, мониторить

### 5. MITIGATE — устранение

В зависимости от решения:

#### Hotfix через /solve:
1. Создать задачу в YouTrack (если не существует):
   ```bash
   pcurl @{yt_profile} 'https://{yt_host}/api/issues' -s -X POST \
     -H 'Content-Type: application/json' \
     -d '{"project":{"id":"{project_id}"},"summary":"[INCIDENT] {summary}","description":"{root_cause_description}"}'
   ```
2. Запустить `/solve {TASK_ID}` — пройти полный цикл
3. После деплоя — проверить что метрики вернулись в норму

#### Проверка после fix:
```bash
# Error rate должен вернуться к baseline
pcurl @{prom_profile} 'https://{prom_host}/api/v1/query' -s -G \
  --data-urlencode 'query=rate(app_http_response_count_total{job="{job}",code=~"5.."}[5m])'

# Sentry: issue resolved
pcurl @{sentry_profile} 'https://{sentry_host}/api/0/issues/{issue_id}/' -s -X PUT \
  -H 'Content-Type: application/json' \
  -d '{"status": "resolved"}'
```

### ⏸ HITL: Подтверждение устранения

Показать:
- Метрики до/после
- Sentry: issue resolved?
- API: healthcheck OK?

Пользователь подтверждает что инцидент закрыт.

### 6. POSTMORTEM — документирование

Сохранить `docs/llm/incidents/{date}-{slug}.md`:

```markdown
# Incident: {summary}

## Metadata
- **Date:** {date}
- **Duration:** {start} — {end} ({duration})
- **Severity:** {P1/P2/P3}
- **Detected by:** {Sentry alert / user report / monitoring}
- **Resolved by:** {hotfix / rollback / config change}
- **Task:** {TASK_ID} (если есть)

## Summary
{1-2 предложения: что случилось и какой был impact}

## Timeline
| Время (UTC) | Событие |
|-------------|---------|
| {time} | {event} |

## Root Cause
{описание причины}

## Impact
- **Users affected:** {estimate}
- **Requests failed:** {count/rate}
- **Duration:** {time}
- **Data loss:** {yes/no, details}

## Resolution
{что было сделано для устранения}

## Metrics
- Error rate: {before} → {during} → {after}
- Latency p99: {before} → {during} → {after}

## Lessons Learned
### What went well
- {positive}

### What went wrong
- {negative}

## Action Items
| # | Action | Owner | Deadline | Status |
|---|--------|-------|----------|--------|
| 1 | {action} | {owner} | {date} | Open |
```

### ⏸ HITL: Утверждение post-mortem

Показать post-mortem пользователю. Пользователь может:
- **Утвердить** — сохранить файл
- **Дополнить** — добавить lessons learned, action items
- **Пропустить** — не создавать post-mortem (P3 инциденты)

---

## Правила

- **Скорость важнее полноты** — на этапе TRIAGE собирать быстро, детали потом
- Не тратить время на post-mortem пока инцидент не устранён
- Hotfix через `/solve` — полный цикл, включая /go-review (даже под давлением)
- Если причина не в нашем коде (зависимость, инфра) — зафиксировать и эскалировать
- Post-mortem — без blame, фокус на процессах и предотвращении
- Action items должны быть конкретными и иметь owner
