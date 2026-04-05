---
name: errors
description: "Errors — дайджест ошибок за период из Sentry, Prometheus, Loki, Kibana."
---

# /errors — Дайджест ошибок

Сводка по ошибкам за период — быстрый обзор "что ломается". Не расследование (для этого /investigate).
Конкретные подключения из `.claude/memory/project-index.md`.

## Триггер

- "какие ошибки за сегодня?"
- "дайджест ошибок за неделю"
- "что ломается в {service}?"
- "top ошибок за 24h"

## Входные данные

- **Период:** default 24h. Варианты: 1h, 24h, 7d, 14d, 30d
- **Проект:** опционально (default: все)

## Шаги (параллельно)

### 1. Sentry: top issues (скилл /sentry)

```bash
# Top по частоте
pcurl @{sentry_profile} 'https://{sentry_host}/api/0/organizations/{org}/issues/?query=is:unresolved&sort=freq&statsPeriod={period}&limit=15' -s

# Новые issues
pcurl @{sentry_profile} 'https://{sentry_host}/api/0/organizations/{org}/issues/?query=is:unresolved+firstSeen:>-{period}&sort=date&limit=10' -s
```

### 2. Prometheus: RPC и HTTP errors (скилл /prometheus)

ВАЖНО: метрика `app_rpc_error_requests_total` (НЕ app_rpc_request_total).

```bash
# Top RPC ошибки по методу
pcurl @{prom_profile} 'https://{prom_host}/api/v1/query' -s -G \
  --data-urlencode 'query=topk(10, sum by (job, method, code) (increase(app_rpc_error_requests_total[{period}])))'

# HTTP 5xx по сервису
pcurl @{prom_profile} 'https://{prom_host}/api/v1/query' -s -G \
  --data-urlencode 'query=sum by (job, code) (increase(app_http_requests_total{code=~"5.."}[{period}]))'
```

### 3. Loki: application errors (скилл /loki)

```bash
# Количество ошибок за период
pcurl @{grafana_profile} "https://{grafana_host}/api/datasources/uid/{loki_uid}/resources/query_range" -s -G \
  --data-urlencode 'query=count_over_time({service_name="{service}"} | json | level="ERROR" [{period}])' \
  --data-urlencode "start=$(date -v-{period_flag} +%s)000000000" \
  --data-urlencode "end=$(date +%s)000000000" \
  --data-urlencode 'step=3600'
```

### 4. Kibana: nginx errors (скилл /kibana, если есть)

```bash
# 5xx count за период
pcurl @{kibana_profile} 'https://{kibana_host}/api/console/proxy?path=nginx-access-*/_search&method=POST' \
  -s -H 'osd-xsrf: true' -H 'Content-Type: application/json' \
  -d '{"query":{"bool":{"must":[{"range":{"httpStatus":{"gte":500}}},{"range":{"@timestamp":{"gte":"now-{period}"}}}]}},"size":0,"aggs":{"by_status":{"terms":{"field":"httpStatus","size":10}}}}'
```

## Отчёт

```markdown
## Error Digest: {period}

**Sentry:** {total_events} events, {total_users} affected users, {new_count} новых issues
**Loki:** {error_count} application errors
**Kibana:** {nginx_5xx} nginx 5xx
**Prometheus:** RPC error rate {rate}%

### Top Issues (Sentry)
| # | Project | Issue | Events | Users | First seen | Ссылка |
|---|---------|-------|--------|-------|------------|--------|

### Новые Issues
| # | Project | Issue | First seen | Ссылка |
|---|---------|-------|------------|--------|

### RPC Errors (Prometheus)
| Job | Method | Code | Count |
|-----|--------|------|-------|

### Ссылки
- [Sentry: unresolved]({url})
- [Grafana: dashboard]({url})
```

## Режим "покопать"

Если пользователь просит разобраться с конкретным issue:

1. Latest event (stacktrace, breadcrumbs):
   ```bash
   pcurl @{sentry_profile} 'https://{sentry_host}/api/0/issues/{issue_id}/events/latest/' -s
   ```

2. Tags (распределение по browser/os/url):
   ```bash
   pcurl @{sentry_profile} 'https://{sentry_host}/api/0/issues/{issue_id}/tags/' -s
   ```

3. Логи по методу из ошибки (Loki):
   ```bash
   pcurl @{grafana_profile} "https://{grafana_host}/api/datasources/uid/{loki_uid}/resources/query_range" -s -G \
     --data-urlencode 'query={service_name="{service}"} | json | level="ERROR" | method="{rpc_method}"' \
     --data-urlencode "start=$(date -v-1H +%s)000000000" \
     --data-urlencode "end=$(date +%s)000000000" \
     --data-urlencode 'limit=20'
   ```

4. Если нужно глубже — вызвать `/investigate`. Для production-инцидента с mitigation — `/incident`.
