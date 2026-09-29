---
name: incident
description: "Incident — реакция на production-инцидент: сбор данных, timeline, root cause, hotfix, post-mortem. Используй когда пользователь сообщает об инциденте/падении на prod и нужен полный цикл реакции с артефактами."
argument-hint: "[описание | TASK_ID | URL алерта]"
---

# Incident — реакция на production инцидент

Структурированный workflow для расследования и устранения production-инцидента: быстрая оценка масштаба, сбор данных, timeline, root cause, hotfix, post-mortem.

Подключения — из `project-index.md` в auto-memory проекта и `~/.claude/memory/infra-{group}.md`. `{prod_branch}` — ветка production из секции «Ветвление» infra-файла (обычно `master`).

## Использование

```
/incident "500 ошибки на /api/v1/orders"
/incident "не работает авторизация"
/incident PLF-900
```

Можно передать описание проблемы, ID задачи в YouTrack (если уже заведена) или URL из Sentry / Grafana alert.

## Flow

```
TRIAGE → GATHER → TIMELINE → ROOT CAUSE → ⏸ HITL → MITIGATE → ⏸ HITL → POSTMORTEM → ⏸ HITL
```

⏸ HITL — вопрос пользователю через AskUserQuestion с перечисленными вариантами.

---

### 1. TRIAGE — оценка масштаба

Быстрая оценка, запросы параллельно, в пределах пары минут:

```bash
# Sentry: всплеск ошибок за последний час
pcurl @{sentry_profile} 'https://{sentry_host}/api/0/organizations/{org}/issues/?query=is:unresolved+project:{sentry_slug}&sort=freq&statsPeriod=1h&limit=10' -s

# Prometheus: доля HTTP 5xx
pcurl @{prom_profile} 'https://{prom_host}/api/v1/query' -s -G \
  --data-urlencode 'query=sum(rate(app_http_requests_total{job="{job}",code=~"5.."}[5m])) / sum(rate(app_http_requests_total{job="{job}"}[5m]))'

# Prometheus: доля ошибок RPC
pcurl @{prom_profile} 'https://{prom_host}/api/v1/query' -s -G \
  --data-urlencode 'query=sum(rate(app_rpc_error_requests_total{job="{job}"}[5m])) / sum(rate(app_rpc_responses_duration_seconds_count{job="{job}"}[5m]))'

# Prometheus: средняя latency RPC по методам
pcurl @{prom_profile} 'https://{prom_host}/api/v1/query' -s -G \
  --data-urlencode 'query=sum(rate(app_rpc_responses_duration_seconds_sum{job="{job}"}[5m])) by (method) / sum(rate(app_rpc_responses_duration_seconds_count{job="{job}"}[5m])) by (method)'

# Жив ли сервис (/status снаружи недоступен)
pcurl @{prom_profile} 'https://{prom_host}/api/v1/query' -s -G --data-urlencode 'query=up{job="{job}"}'

# Nomad: статус аллокаций
pcurl @{nomad_profile} 'https://{nomad_host}/v1/job/{nomad_job}/allocations' -s
```

Severity:

| Severity | Критерии | Действия |
|----------|----------|----------|
| **P1 Critical** | Сервис недоступен, >50% запросов 5xx, потеря данных | Немедленный hotfix, оповещение |
| **P2 Major** | Деградация, >10% ошибок, часть функций недоступна | Hotfix в приоритете |
| **P3 Minor** | Единичные ошибки, не влияет на основной flow | Плановое исправление |

### 2. GATHER — сбор данных

Основной сбор — через `/investigate`: передай симптом, период инцидента и сервис. Он проверит Sentry (с stacktrace top-issues), Prometheus, Loki, Nomad, Kibana, Grafana annotations, зависимые сервисы и вернёт отчёт.

Параллельно собери то, что нужно именно для инцидента:

```bash
# Nomad: последние деплои
pcurl @{nomad_profile} 'https://{nomad_host}/v1/job/{nomad_job}/deployments' -s

# GitLab: последние pipeline на production-ветке
pcurl @{gl_profile} 'https://{gl_host}/api/v4/projects/{gl_project_id}/pipelines?ref={prod_branch}&per_page=3&order_by=id&sort=desc' -s

# Sentry: release и commit задеплоенной версии
pcurl @{sentry_profile} 'https://{sentry_host}/api/0/projects/{org}/{sentry_slug}/releases/?per_page=3' -s
```

Что изменилось в последнем деплое — по коммитам задеплоенных релизов, а не по HEAD:

```bash
git fetch origin {prod_branch} --quiet
git log --oneline {prev_release_commit}..{release_commit}
git diff {prev_release_commit}..{release_commit} --stat
```

### 3. TIMELINE — хронология

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

Найди **trigger event** — что изменилось непосредственно перед началом ошибок: деплой, изменение конфигурации, рост нагрузки, падение зависимости (другой сервис, БД).

### 4. ROOT CAUSE — причина

- **Что сломалось** — компонент, метод, запрос
- **Почему** — баг в коде, конфиг, инфраструктура, зависимость
- **Когда началось** — точное время и trigger
- **Масштаб** — сколько пользователей и запросов затронуто

Если причина в коде — найди коммит в диапазоне релизов из шага 2 (`git log --oneline -5 -- {file}` по проблемному файлу).

### ⏸ HITL: Утверждение диагноза

Показать severity, timeline, root cause, trigger и impact. Предложить действие:
- **Hotfix** — исправить через `/solve` (создать задачу, если её нет)
- **Rollback** — откатить деплой (делает пользователь)
- **Config fix** — изменить конфигурацию
- **Wait** — проблема в зависимости, мониторить

### 5. MITIGATE — устранение

#### Hotfix через /solve

1. Создать задачу в YouTrack, если её нет (описание многострочное — JSON через jq):
   ```bash
   pcurl @{yt_profile} 'https://{yt_host}/api/issues?fields=idReadable' -s -X POST \
     -H 'Content-Type: application/json' \
     -d "$(jq -n --arg p '{project_id}' --arg s "[INCIDENT] $SUMMARY" --arg d "$ROOT_CAUSE" \
           '{project: {id: $p}, summary: $s, description: $d}')"
   ```
2. `/solve {TASK_ID}` — полный цикл, включая /go-review, даже под давлением.
3. После деплоя — проверить, что метрики вернулись к baseline.

#### Проверка после fix

```bash
# Доля 5xx должна вернуться к baseline
pcurl @{prom_profile} 'https://{prom_host}/api/v1/query' -s -G \
  --data-urlencode 'query=sum(rate(app_http_requests_total{job="{job}",code=~"5.."}[5m])) / sum(rate(app_http_requests_total{job="{job}"}[5m]))'

# Sentry: появляются ли новые события по issue
pcurl @{sentry_profile} 'https://{sentry_host}/api/0/issues/{issue_id}/' -s
```

### ⏸ HITL: Подтверждение устранения

Показать метрики до/после, состояние issue в Sentry и healthcheck API. Пользователь подтверждает, что инцидент закрыт.

После подтверждения — перевести issue в Sentry в resolved:
```bash
pcurl @{sentry_profile} 'https://{sentry_host}/api/0/issues/{issue_id}/' -s -X PUT \
  -H 'Content-Type: application/json' -d '{"status": "resolved"}'
```

### 6. POSTMORTEM — документирование

Сохранить `docs/llm/incidents/{YYYY-MM-DD}-{slug}/postmortem.md` (рядом с `report.md` от /investigate):

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
- Latency: {before} → {during} → {after}

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

- **Утвердить** — сохранить файл
- **Дополнить** — добавить lessons learned, action items
- **Пропустить** — не создавать post-mortem (P3)

---

## Правила

- На TRIAGE скорость важнее полноты — детали на GATHER
- Post-mortem — только после устранения инцидента
- Hotfix через `/solve` — полный цикл, включая /go-review
- Причина не в нашем коде (зависимость, инфраструктура) — зафиксировать и эскалировать
- Post-mortem без поиска виноватых: фокус на процессах и предотвращении
- Action items конкретные и с owner
