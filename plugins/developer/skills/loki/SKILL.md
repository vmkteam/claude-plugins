---
name: loki
description: "Loki — JSON-логи сервисов (appkit) через LogQL и Grafana proxy. Используй для поиска по application-логам сервиса за период: ошибки, медленные запросы, трейсы по X-Request-ID."
---

# Loki — логи vmkteam-сервисов

Loki для логов. Доступен через Grafana datasource proxy. Структурированные JSON-логи из Go-сервисов (appkit).

## Подключение

```
Profile: @{grafana_profile} (через datasource proxy)
Datasource UID: {loki_uid}
```

Два способа доступа:

| Способ | Base URL |
|--------|----------|
| UID-based (рекомендуется) | `https://{grafana_host}/api/datasources/uid/{loki_uid}/resources/` |
| Legacy ID-based | `https://{grafana_host}/api/datasources/proxy/{loki_id}/loki/api/v1/` |

**ВАЖНО:** UID-based путь — `/resources/query_range`, `/resources/labels` (без `/loki/api/v1/` префикса). Legacy — с `/loki/api/v1/`.

## ВАЖНО: Stream labels vs JSON fields

Stream labels (можно использовать в `{...}` selector):
- `service_name` — сервис
- `_node` — хост/нода
- `_instance` — UUID инстанса
- `_version` — версия деплоя

JSON fields (доступны ТОЛЬКО через `| json | field=value`):
- `level` — INFO, ERROR, WARN
- `method` — RPC метод
- `platform` — desktop, iOS, android, mobile
- `durationMS` — длительность в ms (число)
- `err` — текст ошибки (`<nil>` если нет)
- `msg` — тип записи (rpc, http, etc.)
- `ip`, `country`, `version`, `userAgent`

**НЕ ИСПОЛЬЗУЙ** level, method, platform в `{...}` selector — только через `| json |`.

Правильно: `{service_name="{service}"} | json | level="ERROR"`
Неправильно: `{service_name="{service}",level="ERROR"}`

## Формат лог-записи (appkit JSON)

```json
{
  "time": "2026-04-03T12:00:28.995Z",
  "level": "INFO",
  "msg": "rpc",
  "method": "lists.episodesunwatched",
  "duration": "116.582386ms",
  "durationMS": 116,
  "err": "<nil>",
  "platform": "desktop",
  "ip": "128.65.1.139"
}
```

## Команды pcurl

### Поиск логов (UID-based)
```bash
# Логи сервиса за 5 минут
pcurl @{profile} "https://{grafana_host}/api/datasources/uid/{loki_uid}/resources/query_range" -s -G \
  --data-urlencode 'query={service_name="{service}"}' \
  --data-urlencode "start=$(date -v-5M +%s)000000000" \
  --data-urlencode "end=$(date +%s)000000000" \
  --data-urlencode 'limit=50'

# Только ошибки
pcurl @{profile} "https://{grafana_host}/api/datasources/uid/{loki_uid}/resources/query_range" -s -G \
  --data-urlencode 'query={service_name="{service}"} | json | level="ERROR"' \
  --data-urlencode "start=$(date -v-1H +%s)000000000" \
  --data-urlencode "end=$(date +%s)000000000" \
  --data-urlencode 'limit=50'

# По RPC методу
pcurl @{profile} "https://{grafana_host}/api/datasources/uid/{loki_uid}/resources/query_range" -s -G \
  --data-urlencode 'query={service_name="{service}"} | json | method="{rpc_method}"' \
  --data-urlencode "start=$(date -v-1H +%s)000000000" \
  --data-urlencode "end=$(date +%s)000000000" \
  --data-urlencode 'limit=50'

# Медленные запросы (>500ms)
pcurl @{profile} "https://{grafana_host}/api/datasources/uid/{loki_uid}/resources/query_range" -s -G \
  --data-urlencode 'query={service_name="{service}"} | json | durationMS > 500' \
  --data-urlencode "start=$(date -v-1H +%s)000000000" \
  --data-urlencode "end=$(date +%s)000000000" \
  --data-urlencode 'limit=50'

# По тексту (line filter — быстрее)
pcurl @{profile} "https://{grafana_host}/api/datasources/uid/{loki_uid}/resources/query_range" -s -G \
  --data-urlencode 'query={service_name="{service}"} |~ "{search_text}"' \
  --data-urlencode "start=$(date -v-1H +%s)000000000" \
  --data-urlencode "end=$(date +%s)000000000" \
  --data-urlencode 'limit=50'

# Ошибки с текстом err (исключая <nil>)
pcurl @{profile} "https://{grafana_host}/api/datasources/uid/{loki_uid}/resources/query_range" -s -G \
  --data-urlencode 'query={service_name="{service}"} | json | err!="<nil>"' \
  --data-urlencode "start=$(date -v-1H +%s)000000000" \
  --data-urlencode "end=$(date +%s)000000000" \
  --data-urlencode 'limit=50'
```

### Metadata
```bash
pcurl @{profile} 'https://{grafana_host}/api/datasources/uid/{loki_uid}/resources/labels' -s
pcurl @{profile} 'https://{grafana_host}/api/datasources/uid/{loki_uid}/resources/label/service_name/values' -s
```

## LogQL reference

### Stream selectors
```logql
{service_name="{service}"}
{service_name=~"{service1}|{service2}"}
{service_name="{service}",_node="{node}"}
```

### JSON parsing + фильтры
```logql
{service_name="{service}"} | json | level="ERROR"
{service_name="{service}"} | json | method="{method}" | durationMS > 500
{service_name="{service}"} | json | err!="<nil>"
```

### Line filters
```logql
{service_name="{service}"} |= "error"
{service_name="{service}"} |~ "timeout|deadline"
{service_name="{service}"} != "healthcheck"
```

## Обработка ответов

- `data.result[].stream` — stream labels
- `data.result[].values[][0]` — timestamp в наносекундах (string!)
- `data.result[].values[][1]` — JSON string лог-записи
