---
name: nomad
description: "Nomad — оркестрация сервисов. Метрики через Prometheus, API через pcurl."
---

# Nomad — оркестрация сервисов

HashiCorp Nomad для оркестрации. Метрики через Prometheus, API через pcurl.

## Подключение

```
Prometheus metrics: job="nomad_metrics"
Nomad API profile: @{nomad_profile} (если есть)
```

## Метрики через Prometheus

### Здоровье кластера
```bash
pcurl @{prom_profile} 'https://{prom_host}/api/v1/query' -s -G --data-urlencode 'query=nomad_nomad_autopilot_healthy'
```

### Allocations
```bash
pcurl @{prom_profile} 'https://{prom_host}/api/v1/query' -s -G --data-urlencode 'query=nomad_client_allocations_running'
pcurl @{prom_profile} 'https://{prom_host}/api/v1/query' -s -G --data-urlencode 'query=nomad_client_allocations_blocked'
pcurl @{prom_profile} 'https://{prom_host}/api/v1/query' -s -G --data-urlencode 'query=nomad_client_allocs_oom_killed'
pcurl @{prom_profile} 'https://{prom_host}/api/v1/query' -s -G --data-urlencode 'query=nomad_client_allocs_restart'
```

### Ресурсы нод
```bash
pcurl @{prom_profile} 'https://{prom_host}/api/v1/query' -s -G --data-urlencode 'query=nomad_client_host_cpu_total_percent'
pcurl @{prom_profile} 'https://{prom_host}/api/v1/query' -s -G --data-urlencode 'query=nomad_client_host_memory_available'
pcurl @{prom_profile} 'https://{prom_host}/api/v1/query' -s -G --data-urlencode 'query=nomad_client_host_disk_used_percent'
```

### Per-alloc ресурсы
```bash
pcurl @{prom_profile} 'https://{prom_host}/api/v1/query' -s -G --data-urlencode 'query=nomad_client_allocs_cpu_total_percent'
pcurl @{prom_profile} 'https://{prom_host}/api/v1/query' -s -G --data-urlencode 'query=nomad_client_allocs_memory_rss'
```

### Тренды (range)
```bash
pcurl @{prom_profile} 'https://{prom_host}/api/v1/query' -s -G --data-urlencode 'query=increase(nomad_client_allocs_oom_killed[{period}])'
pcurl @{prom_profile} 'https://{prom_host}/api/v1/query' -s -G --data-urlencode 'query=increase(nomad_client_allocs_restart[{period}])'
```

## Nomad API
```bash
pcurl @{nomad_profile} 'https://{nomad_host}/v1/jobs' -s
pcurl @{nomad_profile} 'https://{nomad_host}/v1/job/{job_id}' -s
pcurl @{nomad_profile} 'https://{nomad_host}/v1/job/{job_id}/allocations' -s
pcurl @{nomad_profile} 'https://{nomad_host}/v1/job/{job_id}/deployment' -s
pcurl @{nomad_profile} 'https://{nomad_host}/v1/nodes' -s
pcurl @{nomad_profile} 'https://{nomad_host}/v1/client/fs/logs/{alloc_id}?task={task}&type=stdout&plain=true' -s
```

## При инцидентах проверять

1. **OOM kills** — `nomad_client_allocs_oom_killed`
2. **Restarts** — `nomad_client_allocs_restart`
3. **Blocked** — `nomad_client_allocations_blocked`
4. **Failed** — `nomad_client_allocs_failed`
5. **Node resources** — CPU, memory, disk
