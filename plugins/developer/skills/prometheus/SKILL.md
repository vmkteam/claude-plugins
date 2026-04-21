---
name: prometheus
description: "Prometheus — PromQL-запросы к метрикам appkit/zenrpc/cron. Используй когда нужны метрики сервиса: RPS, latency p95/p99, error rate, статус cron-задач, использование ресурсов."
---

# Prometheus — метрики vmkteam-сервисов

Prometheus для метрик. Метрики из vmkteam/appkit, vmkteam/zenrpc, vmkteam/cron.

Конкретные хосты, job-имена определяются при онбординге.

## Подключение

```
Profile: @{prom_profile}
Base URL: https://{prom_host}/api/v1
```

Также доступен через Grafana proxy (см. /grafana).

## Метрики appkit (app_*)

### HTTP (app_http_*)

| Метрика | Тип | Labels |
|---------|-----|--------|
| `app_http_requests_total` | counter | job, code, method, uri, server |
| `app_http_responses_duration_seconds_count` | counter | job, code, method, uri, server |
| `app_http_responses_duration_seconds_sum` | counter | job, code, method, uri, server |
| `app_http_client_requests_total` | counter | job |
| `app_http_client_requests_inflight` | gauge | job |

### RPC / zenrpc (app_rpc_*)

| Метрика | Тип | Labels |
|---------|-----|--------|
| `app_rpc_responses_duration_seconds_count` | counter | job, code, method, platform, server, version |
| `app_rpc_responses_duration_seconds_sum` | counter | job, code, method, platform, server, version |
| `app_rpc_error_requests_total` | counter | job, code, method, platform, server, version |

### Cron (app_cron_*)

| Метрика | Тип | Labels |
|---------|-----|--------|
| `app_cron_active` | gauge | job |
| `app_cron_evaluated_total` | counter | job |
| `app_cron_evaluated_duration_seconds_*` | counter | job |

### Прочие

| Метрика | Описание |
|---------|----------|
| `app_log_events_total` | Log events |
| `app_metadata_db_connections_total` | DB connections |

## Labels

| Label | Описание |
|-------|----------|
| `job` | Сервис (определяется при онбординге) |
| `code` | HTTP/RPC status code |
| `method` | HTTP method или RPC method name (lowercase) |
| `uri` | HTTP URI |
| `platform` | Клиентская платформа (RPC) |
| `version` | Версия клиента (RPC) |

## Команды pcurl

### Instant query
```bash
# Общий формат (--data-urlencode обязателен для query с фигурными скобками)
pcurl @{profile} 'https://{host}/api/v1/query' -s -G --data-urlencode 'query={promql}'

# Health
pcurl @{profile} 'https://{host}/api/v1/query' -s -G --data-urlencode 'query=up{job="{service}"}'

# RPC RPS
pcurl @{profile} 'https://{host}/api/v1/query' -s -G --data-urlencode 'query=sum(rate(app_rpc_responses_duration_seconds_count{job="{service}"}[5m]))'

# RPC error rate
pcurl @{profile} 'https://{host}/api/v1/query' -s -G --data-urlencode 'query=sum(rate(app_rpc_error_requests_total{job="{service}"}[5m]))/sum(rate(app_rpc_responses_duration_seconds_count{job="{service}"}[5m]))'
```

### Range query
```bash
pcurl @{profile} 'https://{host}/api/v1/query_range' -s -G \
  --data-urlencode 'query={promql}' \
  --data-urlencode "start=$(date -v-1H +%s)" \
  --data-urlencode "end=$(date +%s)" \
  --data-urlencode 'step=60'
```

### Metadata
```bash
pcurl @{profile} 'https://{host}/api/v1/label/job/values' -s
pcurl @{profile} 'https://{host}/api/v1/label/method/values' -s -G --data-urlencode 'match[]=app_rpc_responses_duration_seconds_count{job="{service}"}'
```

## Полезные PromQL

### RPC (основные для расследований)
```promql
# RPS по методу
sum(rate(app_rpc_responses_duration_seconds_count{job="{service}"}[5m])) by (method)

# Error rate
sum(rate(app_rpc_error_requests_total{job="{service}"}[5m])) / sum(rate(app_rpc_responses_duration_seconds_count{job="{service}"}[5m]))

# Avg latency по методу
sum(rate(app_rpc_responses_duration_seconds_sum{job="{service}"}[5m])) by (method) / sum(rate(app_rpc_responses_duration_seconds_count{job="{service}"}[5m])) by (method)

# Top-10 ошибок
topk(10, sum(rate(app_rpc_error_requests_total{job="{service}"}[5m])) by (method, code))

# Top-10 медленных методов
topk(10, sum(rate(app_rpc_responses_duration_seconds_sum{job="{service}"}[5m])) by (method) / sum(rate(app_rpc_responses_duration_seconds_count{job="{service}"}[5m])) by (method))
```

### HTTP
```promql
sum(rate(app_http_requests_total{job="{service}"}[5m]))
sum(rate(app_http_requests_total{job="{service}",code=~"5.."}[5m]))
```

### Saturation
```promql
go_goroutines{job="{service}"}
process_resident_memory_bytes{job="{service}"}
rate(process_cpu_seconds_total{job="{service}"}[5m])
app_metadata_db_connections_total{job="{service}"}
```

### Node Exporter (инфраструктура)

Jobs: `node_exporter`, `consul_node_exporter`.

```promql
# CPU usage по нодам
100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Memory usage
node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes

# Memory available %
node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes * 100

# Disk available
node_filesystem_avail_bytes{mountpoint="/"}

# Disk usage %
100 - (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"} * 100)

# Load average
node_load1
node_load5
node_load15

# Network traffic
rate(node_network_receive_bytes_total{device="eth0"}[5m])
rate(node_network_transmit_bytes_total{device="eth0"}[5m])

# Disk I/O
rate(node_disk_io_time_seconds_total[5m])
```

### Service Metadata (topology)

```promql
# Какие сервисы существуют (version, зависимости)
app_metadata_service

# Межсервисные связи (sync/async/external)
app_metadata_services

# Подключения к БД
app_metadata_db_connections_total
```

## Обработка ответов

Instant: `data.result[].metric` + `data.result[].value[1]` (string!)
Range: `data.result[].metric` + `data.result[].values[][1]` (string!)
