---
name: investigate
description: "Investigate — расследование проблемы по всем data sources (Sentry, Prometheus, Loki, Kibana, Nomad). Используй когда есть симптом (ошибка, деградация, аномалия), но причина неизвестна, а полноценный /incident избыточен."
argument-hint: "[описание проблемы, период, сервис]"
allowed-tools: "Bash(pcurl:*)"
---

# /investigate — расследование проблемы

Найти причину симптома и подтвердить её данными из всех доступных источников. Какие источники есть — зависит от стадии проекта; подключения — из `project-index.md` в auto-memory проекта и `~/.claude/memory/infra-{group}.md`.

Примеры запросов: «API тормозит», «500 ошибки на /rpc/», «у пользователя не работает X», «что-то сломалось после деплоя».

> Для полного workflow production-инцидента с HITL, mitigation и post-mortem — `/incident`.

## Входные данные

- Описание проблемы (свободный текст)
- Период — по умолчанию последний час
- Сервис — по умолчанию все из project-index

## Как расследовать

Цель — гипотеза о root cause, подтверждённая данными, либо честный вывод, что данных не хватает. Остановись, когда причина подтверждена двумя независимыми источниками (например, всплеск в Sentry и рост error rate в Prometheus в то же время) или когда все доступные источники проверены.

1. **Scope.** Из описания извлеки время начала, сервис, конкретный RPC-метод или URL и ключевые слова для поиска.
2. **Жив ли сервис** (/api-health) — первым делом:
   ```bash
   pcurl @{api_prod_profile} https://{api_prod_host}/{rpc_endpoint} -s -L -X POST \
     -H 'Content-Type: application/json' \
     -d '{"jsonrpc":"2.0","method":"{known_method}","params":{},"id":1}' \
     -w '\nHTTP %{http_code} | Total: %{time_total}s | TTFB: %{time_starttransfer}s\n'
   ```
   Не отвечает — сразу к Nomad.
3. **Источники — параллельно.** Начни с одного-двух обзорных запросов к каждому и углубляйся туда, где есть сигнал. Источник без аномалий в отчёте — одной строкой.
4. **Деплои.** Сопоставь начало проблемы с деплоями (Sentry releases, Grafana annotations). Недавний деплой — посмотри, что в нём изменилось.
5. **Код.** Есть гипотеза (stacktrace, подозрительный метод) — найди код локально и сверяй с задеплоенной версией (commit из Sentry release), а не с HEAD: `git diff {release_commit}..HEAD --stat`.
6. **Отчёт** — сохрани в `docs/llm/incidents/{YYYY-MM-DD}-{slug}/report.md` и покажи. Если запись файлов недоступна (plan mode — например, вызов из ANALYZE в /solve), верни отчёт целиком текстом: его сохранит вызывающий скилл.

## Источники

**Sentry** (/sentry): unresolved issues за период по частоте; новые issues (firstSeen в периоде); поиск по ключевым словам. Для top-3 — latest event (stacktrace, breadcrumbs).

**Prometheus** (/prometheus): RPC error rate и HTTP 5xx; latency по методам (средняя, top медленных); RPS в сравнении с обычным уровнем; saturation — goroutines, память, DB connections.

**Loki** (/loki): ошибки сервиса (`| json | level="ERROR"`), логи конкретного метода, медленные запросы (`durationMS > 500`), записи с ошибкой (`err!="<nil>"`).

**Nomad** (/nomad): инфраструктурные причины — OOM kills (`increase(nomad_client_allocs_oom_killed[{period}])`), рестарты (`increase(nomad_client_allocs_restart[{period}])`), blocked allocations, ресурсы нод.

**Kibana / OpenSearch** (/kibana, если есть): 5xx и медленные запросы (`requestTime > 1`) в nginx-access, записи nginx-error.

**Grafana** (/grafana): annotations за период (деплои, инциденты) и ссылки на дашборды:
```bash
pcurl @{grafana_profile} 'https://{grafana_host}/api/annotations?from='$(date -v-{period} +%s)000'&to='$(date +%s)000'&limit=20' -s
```

**Зависимые сервисы** — из секции «Связанные сервисы» project-index: есть ли в тот же период ошибки в Sentry и рост error rate у них.

**YouTrack** (/youtrack): возможно, проблема уже известна:
```bash
pcurl @{yt_profile} 'https://{yt_host}/api/issues?query=project:{PROJECT}+{keywords}&fields=idReadable,summary&$top=5' -s
```

## Формат отчёта

Секции для недоступных источников и источников без аномалий не раздувай — одна строка «проверено, аномалий нет» или «нет доступа».

```markdown
## Incident Report

**Время:** {start} — {end}
**Severity:** Critical / High / Medium / Low
**Affected:** {services}, {endpoints}

### Root Cause
{гипотеза и данные, которые её подтверждают; что осталось неподтверждённым}

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

### Логи (Loki, Kibana)
- {количество ошибок, top сообщений, 5xx и медленные запросы в nginx}

### Зависимые сервисы
| Сервис | Sentry errors | Error rate |
|--------|---------------|------------|

### Деплои
- Последний деплой: {version} в {time}

### Ссылки
- [Sentry issues]({url})
- [Grafana dashboard]({url})
- [YouTrack]({url}) — если найден существующий тикет

### Рекомендации
- {action items}
- Тикет в YouTrack: {нужен / уже есть {ID}}
```

## Правила

- Используй только системы, доступные на стадии проекта (из project-index)
- Данных мало — так и скажи, не додумывай
- В отчёте — прямые ссылки на дашборды и issues
- Проблема подтверждена, а тикета нет — предложи создать его в YouTrack
