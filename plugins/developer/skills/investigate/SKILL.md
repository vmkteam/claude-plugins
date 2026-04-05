---
name: investigate
description: "Investigate — полное расследование инцидента с использованием всех доступных data sources."
---

# /investigate — Расследование инцидента

Полное расследование инцидента. Задействует все доступные data source скиллы по стадии проекта.
Конкретные подключения из `.claude/memory/project-index.md`.

## Триггер

- "API тормозит"
- "500 ошибки на /rpc/"
- "у пользователя не работает X"

> Для полного workflow production-инцидента с HITL, mitigation и post-mortem — использовать `/incident`.
- "что-то сломалось после деплоя"

## Входные данные

- Описание проблемы (свободный текст)
- Временной диапазон (опционально, default: 1h)
- Проект/сервис (опционально, default: все)

## Алгоритм

### 1. Определить scope

Из описания извлечь:
- **Время:** когда началось? default `statsPeriod=1h`
- **Сервис:** какой именно? Если неизвестно — все из project-index
- **Endpoint/метод:** конкретный RPC method или URL?
- **Ключевые слова:** для поиска в Sentry и логах

### 2. Проверить здоровье (скилл /api-health)

Первым делом — жив ли сервис?

```bash
pcurl @{api_prod_profile} https://{api_prod_host}/{rpc_endpoint} -s -L -X POST \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"{known_method}","params":{},"id":1}' \
  -w '\nHTTP %{http_code} | Total: %{time_total}s | TTFB: %{time_starttransfer}s\n'
```

Если не отвечает — сразу проверять Nomad (шаг 6).

### 3. Sentry: ошибки (скилл /sentry)

Параллельно:
- Unresolved issues за период, по частоте
- Новые issues (firstSeen в периоде)
- По ключевым словам из описания проблемы

Top-3 issues → получить latest event (stacktrace, breadcrumbs).

### 4. Prometheus: метрики (скилл /prometheus)

Параллельно:
- RPC error rate и HTTP 5xx
- Latency (avg по методу, top-10 медленных)
- Throughput (RPS) — сравнить с обычным уровнем
- Saturation: goroutines, memory, DB connections

### 5. Loki: приложенческие логи (скилл /loki)

- Ошибки по сервису (`level="ERROR"`)
- По конкретному методу если известен
- Медленные запросы (`durationMS > 500`)
- Ошибки с текстом (`err!="<nil>"`)

### 6. Nomad: оркестрация (скилл /nomad)

Проверить — не инфраструктурная ли причина:
- OOM kills (`increase(nomad_client_allocs_oom_killed[{period}])`)
- Restarts (`increase(nomad_client_allocs_restart[{period}])`)
- Blocked allocations
- Node resources (CPU, memory)

### 7. Kibana/OpenSearch: nginx логи (скилл /kibana)

Если есть — проверить на уровне reverse proxy:
- HTTP 5xx в nginx-access
- Медленные запросы (`requestTime > 1`)
- Ошибки в nginx-error

### 8. Grafana: деплои и дашборды (скилл /grafana)

- Annotations за период (деплои, инциденты)
- Ссылки на дашборды для отчёта

```bash
pcurl @{grafana_profile} 'https://{grafana_host}/api/annotations?from='$(date -v-{period} +%s)000'&to='$(date +%s)000'&limit=20' -s
```

### 9. Зависимые сервисы

Из project-index.md → секция "Связанные сервисы". Для каждого зависимого сервиса проверить:
- Sentry: есть ли ошибки в зависимых сервисах в тот же период?
- Prometheus: error rate зависимых

### 10. YouTrack: существующие тикеты (скилл /youtrack)

Проверить — может проблема уже известна:
```bash
pcurl @{yt_profile} 'https://{yt_host}/api/issues?query=project:{PROJECT}+{keywords}&fields=idReadable,summary&$top=5' -s
```

### 11. Проверить деплои

Через Sentry releases и Grafana annotations:
- Сопоставить время деплоя с началом проблемы
- Если деплой недавний — посмотреть что изменилось

### 12. Верификация по исходному коду

Когда есть гипотеза (stacktrace, подозрительный метод):
- Найти файл в локальных исходниках
- **Сверять с задеплоенной версией** (Sentry release commit), не с HEAD
- `git diff {release_commit}..HEAD --stat`

### 13. Сформировать и сохранить отчёт

Сохранить в `docs/llm/incidents/{YYYY-MM-DD}-{slug}/report.md`.

## Формат отчёта

```markdown
## Incident Report

**Время:** {start} — {end}
**Severity:** Critical / High / Medium / Low
**Affected:** {services}, {endpoints}

### Timeline
- HH:MM — Release {version} deployed
- HH:MM — Error rate started growing
- HH:MM — First user reports

### Здоровье
- API: {alive/down}, latency: {time}s
- Nomad: OOM={count}, restarts={count}, blocked={count}

### Ошибки (Sentry)
| # | Issue | Events | Users | Trend |
|---|-------|--------|-------|-------|

### Метрики (Prometheus)
- Error rate: {current}% (обычно {baseline}%)
- Latency: {current}ms (обычно {baseline}ms)
- Throughput: {current} RPS (обычно {baseline} RPS)
- Goroutines: {current} | Memory: {current} | DB conns: {current}

### Логи (Loki)
- Errors: {count} за период
- Top ошибки: {list}

### Nginx (Kibana)
- 5xx: {count} за период
- Slow (>1s): {count}

### Зависимые сервисы
| Сервис | Sentry errors | Error rate |
|--------|---------------|------------|

### Деплои
- Последний деплой: {version} в {time}
- Grafana annotations: {list}

### Root Cause
{hypothesis based on data}

### Ссылки
- [Sentry issues]({url})
- [Grafana dashboard]({url})
- [YouTrack]({url}) (если найден существующий тикет)

### Рекомендации
- {action items}
- Создать тикет в YouTrack: {да/нет, какой проект}
```

## Правила

- Шаги 2-10 выполнять **параллельно** где возможно
- Не более 3-5 запросов к каждому источнику
- Использовать только доступные системы по стадии проекта (из project-index)
- Если данных мало — сказать об этом, не придумывать
- Всегда **прямые ссылки** на дашборды и issues
- Предложить создать тикет в YouTrack если проблема подтверждена и тикета нет
