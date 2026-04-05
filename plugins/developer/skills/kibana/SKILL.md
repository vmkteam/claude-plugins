---
name: kibana
description: "Kibana/OpenSearch Dashboards — поиск по логам через Elasticsearch/OpenSearch API и pcurl."
---

# Kibana / OpenSearch Dashboards — логи

OpenSearch Dashboards (или Kibana) для поиска по логам (nginx access/error, application). Приложенческие логи Go-сервисов — в Loki (см. /loki).

Разные индексы содержат разные данные от разных систем. Имена полей зависят от индекса. **Всегда начинай с discovery.**

> OpenSearch Dashboards использует заголовок `osd-xsrf: true` вместо `kbn-xsrf: true` (Kibana).

## Подключение

```
Profile: @{kibana_profile}
Base URL: https://{kibana_host}
Header: osd-xsrf: true (OpenSearch) или kbn-xsrf: true (Kibana)
```

## Шаг 1. Discovery

### Index patterns (рекомендуется — самый надёжный способ)
```bash
pcurl @{profile} 'https://{host}/api/saved_objects/_find?type=index-pattern&per_page=100' -s -H 'osd-xsrf: true'
```

### Пример документа — быстрый способ понять структуру полей
```bash
pcurl @{profile} 'https://{host}/api/console/proxy?path={index}/_search&method=POST' \
  -s -H 'osd-xsrf: true' -H 'Content-Type: application/json' \
  -d '{"sort":[{"@timestamp":"desc"}],"size":1}'
```

### Mapping индекса (полная структура полей)
```bash
pcurl @{profile} 'https://{host}/api/console/proxy?path={index}/_mapping&method=POST' \
  -s -H 'osd-xsrf: true' -H 'Content-Type: application/json' -d '{}'
```

Типичные index patterns:
- `nginx-access-*` — nginx access логи (ip, path, httpStatus, requestTime, serverName, platform, xRequestId)
- `nginx-error-*` — nginx error логи (level, description, connectionId)
- `{service}-*` — приложенческие логи (если не в Loki)
- `logstash-*` — legacy

## Шаг 2. Поиск логов

Использовать реальные имена полей из discovery.

```bash
# По query string
pcurl @{profile} 'https://{host}/api/console/proxy?path={index}/_search&method=POST' \
  -s -H 'osd-xsrf: true' -H 'Content-Type: application/json' \
  -d '{"query":{"query_string":{"query":"{query}"}},"sort":[{"@timestamp":"desc"}],"size":20}'

# За период
pcurl @{profile} 'https://{host}/api/console/proxy?path={index}/_search&method=POST' \
  -s -H 'osd-xsrf: true' -H 'Content-Type: application/json' \
  -d '{"query":{"bool":{"must":[{"query_string":{"query":"{query}"}},{"range":{"@timestamp":{"gte":"now-1h","lte":"now"}}}]}},"sort":[{"@timestamp":"desc"}],"size":50}'

# Nginx: 5xx ошибки
pcurl @{profile} 'https://{host}/api/console/proxy?path=nginx-access-*/_search&method=POST' \
  -s -H 'osd-xsrf: true' -H 'Content-Type: application/json' \
  -d '{"query":{"bool":{"must":[{"range":{"httpStatus":{"gte":500}}},{"range":{"@timestamp":{"gte":"now-1h"}}}]}},"sort":[{"@timestamp":"desc"}],"size":20}'

# Nginx: медленные запросы
pcurl @{profile} 'https://{host}/api/console/proxy?path=nginx-access-*/_search&method=POST' \
  -s -H 'osd-xsrf: true' -H 'Content-Type: application/json' \
  -d '{"query":{"bool":{"must":[{"range":{"requestTime":{"gte":1}}},{"range":{"@timestamp":{"gte":"now-1h"}}}]}},"sort":[{"requestTime":"desc"}],"size":20}'

# По X-Request-ID (trace)
pcurl @{profile} 'https://{host}/api/console/proxy?path=nginx-access-*/_search&method=POST' \
  -s -H 'osd-xsrf: true' -H 'Content-Type: application/json' \
  -d '{"query":{"term":{"xRequestId":"{request_id}"}},"size":10}'
```

## Агрегации

```bash
# Группировка по полю
pcurl @{profile} 'https://{host}/api/console/proxy?path={index}/_search&method=POST' \
  -s -H 'osd-xsrf: true' -H 'Content-Type: application/json' \
  -d '{"query":{"range":{"@timestamp":{"gte":"now-1h"}}},"size":0,"aggs":{"by_field":{"terms":{"field":"{field}","size":20}}}}'

# Histogram по времени
pcurl @{profile} 'https://{host}/api/console/proxy?path={index}/_search&method=POST' \
  -s -H 'osd-xsrf: true' -H 'Content-Type: application/json' \
  -d '{"query":{"range":{"@timestamp":{"gte":"now-1h"}}},"size":0,"aggs":{"over_time":{"date_histogram":{"field":"@timestamp","fixed_interval":"5m"}}}}'
```

## Обработка ответов

- `hits.total.value` — количество записей
- `hits.hits[]._source` — данные записи
- `aggregations` — результаты агрегаций
