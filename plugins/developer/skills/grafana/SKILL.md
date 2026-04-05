---
name: grafana
description: "Grafana — дашборды, Prometheus и Loki proxy через REST API и pcurl."
---

# Grafana — дашборды и proxy

Grafana для дашбордов, метрик (Prometheus) и логов (Loki). Доступ через pcurl.

Конкретные хосты, datasource IDs/UIDs, dashboard UIDs определяются при онбординге.

## Подключение

```
Profile: @{grafana_profile}
Base URL: https://{grafana_host}/api
```

## Команды pcurl

### Дашборды
```bash
pcurl @{profile} 'https://{host}/api/search?type=dash-db' -s
pcurl @{profile} 'https://{host}/api/search?type=dash-db&query={service}' -s
pcurl @{profile} 'https://{host}/api/dashboards/uid/{dashboard_uid}' -s
```

### Datasources
```bash
pcurl @{profile} 'https://{host}/api/datasources' -s
```

### Prometheus через proxy

Два способа (оба работают, UID-based — предпочтительный):

```bash
# UID-based (Grafana 9+, рекомендуется)
pcurl @{profile} 'https://{host}/api/datasources/uid/{prom_uid}/resources/api/v1/query?query={promql}' -s
pcurl @{profile} 'https://{host}/api/datasources/uid/{prom_uid}/resources/api/v1/query_range?query={promql}&start='$(date -v-1H +%s)'&end='$(date +%s)'&step=60' -s

# Legacy ID-based (работает, но deprecated)
pcurl @{profile} 'https://{host}/api/datasources/proxy/{prom_id}/api/v1/query?query={promql}' -s
```

### Loki через proxy

```bash
# UID-based (рекомендуется) — путь /resources/ БЕЗ /loki/api/v1/
pcurl @{profile} "https://{host}/api/datasources/uid/{loki_uid}/resources/query_range" -s -G \
  --data-urlencode 'query={logql}' \
  --data-urlencode "start=$(date -v-1H +%s)000000000" \
  --data-urlencode "end=$(date +%s)000000000" \
  --data-urlencode 'limit=50'

# Labels
pcurl @{profile} 'https://{host}/api/datasources/uid/{loki_uid}/resources/labels' -s

# Legacy ID-based (работает, но deprecated)
pcurl @{profile} "https://{host}/api/datasources/proxy/{loki_id}/loki/api/v1/query_range" -s -G \
  --data-urlencode 'query={logql}' \
  --data-urlencode "start=$(date -v-1H +%s)000000000" \
  --data-urlencode "end=$(date +%s)000000000" \
  --data-urlencode 'limit=50'
```

### Annotations (деплои, инциденты)
```bash
pcurl @{profile} 'https://{host}/api/annotations?from='$(date -v-1H +%s)000'&to='$(date +%s)000'&limit=50' -s
pcurl @{profile} 'https://{host}/api/annotations?dashboardUID={uid}&from='$(date -v-24H +%s)000'&to='$(date +%s)000 -s
```

### Alerts
```bash
pcurl @{profile} 'https://{host}/api/alertmanager/grafana/api/v2/alerts?active=true' -s
pcurl @{profile} 'https://{host}/api/ruler/grafana/api/v1/rules' -s
```

## Прямые ссылки

```
https://{host}/d/{dashboard_uid}?from=now-1h&to=now
https://{host}/d/{dashboard_uid}?var-job={service}&from=now-1h&to=now
https://{host}/explore?schemaVersion=1&panes={"pane":{"datasource":"{prom_uid}","queries":[{"expr":"{promql}"}],"range":{"from":"now-1h","to":"now"}}}
```
