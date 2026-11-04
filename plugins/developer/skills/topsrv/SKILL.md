---
name: topsrv
description: "topsrv — метрики, алерты, CVE и HTTP-логи серверов проекта через публичный JSON-RPC API app.topsrv.io. Используй, когда нужна загрузка CPU, памяти или диска хоста, метрики PostgreSQL/nginx/angie агента topsrv (`topsrv_*`), какие алерты горят, уязвимые пакеты на серверах или кто (боты, сети, IP) нагружает сайт."
allowed-tools: "Bash(pcurl:*)"
---

# topsrv — серверы проекта: метрики, алерты, инвентарь, HTTP-логи

topsrv — агент мониторинга серверов (один бинарь вместо node_exporter, postgres_exporter, process-exporter, nginx-exporter и smartctl_exporter) и сервис app.topsrv.io, куда агенты отправляют метрики, инвентарь пакетов и access-логи. Скилл работает с публичным API v1: один токен — один проект, только чтение, кроме `alert.silence`.

Метрики `topsrv_*` лежат в хранилище topsrv, а не в Prometheus проекта: метрики сервиса (`app_*`) — через `/prometheus`, метрики серверов — здесь.

Профиль определяется при онбординге (`/onboard`) и хранится в `~/.claude/memory/infra-{group}.md`, секция topsrv.

## Подключение

```
Profile:  @{topsrv_profile}                               # обычно topsrv-{slug}; второй токен проекта — topsrv-{slug}-2
Endpoint: POST https://app.topsrv.io/api/v1/rpc/          # JSON-RPC 2.0, слэш в конце обязателен
Contract: https://app.topsrv.io/api/v1/rpc/openrpc.json   # открыт без токена
```

- Профиля нет в infra-файле — найди строки `topsrv-*` в `pcurl show`; если проектов несколько, спроси, какой нужен.
- Профиля нет вообще — попроси пользователя выпустить токен в app.topsrv.io → Project settings → Tokens → API tokens и выполнить команду `pcurl add` с вкладки pcurl. Токен (`tsk_…`) не спрашивай и не печатай.
- Проект берётся из токена, ни один метод не принимает `slug`.
- Сессионный ключ веб-интерфейса (заголовок `Authorization2`) здесь даёт 401 `invalid_token`, а API-токен не работает на внутреннем `/v1/rpc/`.

## Вызов

```bash
pcurl @{topsrv_profile} -sS https://app.topsrv.io/api/v1/rpc/ \
  -d '{"jsonrpc":"2.0","id":1,"method":"meta.whoami"}'
```

- `id` обязателен: тело без него — notification, ответ — пустой 200.
- Параметры — объектом по именам: `"params":{"hostname":"web-1"}`. Имена методов регистронезависимы.
- Кавычки PromQL внутри single-quoted тела экранируй `\"`. Тело с вычисляемыми значениями (окно времени, длинный PromQL) собирай через `jq -nc` в аргумент `-d "$(…)"`: pcurl не передаёт stdin, и `-d @-` даёт `-32700 Parse error`.
- Профиль хранит `Content-Type: application/json`. Если заголовка в профиле нет — добавь `-H 'Content-Type: application/json'`, иначе 415.
- Батч — массив до 10 вызовов, каждый вызов батча стоит единицу rate limit.

Первый вызов в сессии — `meta.whoami`: `project`, `scopes`, `expiresAt`. Метод вне scopes токена отвечает 403 `insufficient_scope` — сообщи пользователю, какой scope нужен. Если до `expiresAt` меньше недели — предупреди.

## Методы

| Метод | Scope | Параметры | Возвращает |
|-------|-------|-----------|------------|
| `meta.whoami` | — | — | `project`, `scopes`, `tokenPrefix`, `expiresAt` |
| `host.list` | hosts:read | — | хосты с метриками за 48 ч: `hostname`, ОС, ядро, `agentVersion`, `lastSeen`, `addresses[]` |
| `host.get` | hosts:read | `hostname` | один хост; 404 `host_not_found` |
| `host.summary` | hosts:read | — | строка на хост: `cpu` %, `memUsed`/`memTotal` байт, `diskMax` %, `load` 1m, `uptime` с |
| `metric.query` | metrics:read | `query` | instant PromQL |
| `metric.queryRange` | metrics:read | `query`, `start`, `end`, `step`? | range PromQL |
| `alert.rules` | alerts:read | — | действующие правила (системные и свои, с override); у открытых — `currentState`, `activeEventId` |
| `alert.list` | alerts:read | `state`?, `severity`?, `host`?, `page`?, `pageSize`? (≤500) | события алертов, новые первыми |
| `alert.silence` | alerts:write | `input`: `matcher`, `startsAt`, `endsAt`, `comment` | созданное окно тишины |
| `inventory.hosts` | inventory:read | — | ОС, ядро, пакеты, `cveCount`/`fixableCount`, `rebootRequired`, `lastAuditAt` |
| `inventory.findings` | inventory:read | `hostname` | открытые уязвимости хоста: пакет, версия, `fixedInVersion`, advisory, CVE |
| `botlog.search` | botlogs:read | `filter`, `limit`? (≤1000), `offset`? | события ботов |
| `weblog.summary` | weblogs:read | `filter` | число запросов, avg/p50/p95 мс, ответы по классам |
| `weblog.top` | weblogs:read | `groupBy`, `filter`, `sortBy`?, `sortDir`?, `limit`? (≤500), `offset`?, `details`? | трафик, сгруппированный по измерению |
| `weblog.networks` | weblogs:read | `filter`, `sortBy`?, `minIPs`?, `limit`? (≤200) | строка на автономную систему |
| `weblog.blockImpact` | weblogs:read | `ip`?, `userAgent`?, `window`? | кого заденет блокировка IP, UA, подсети /24, AS |
| `weblog.search` | weblogs:read | `filter`, `sortDir`?, `limit`? (≤500), `offset`? (≤10000) | сырые события HTTP-потока |

`?` — необязательный параметр. Namespace `inventory`, `botlog`, `weblog` регистрируются, только если у инсталляции включён ClickHouse; иначе вызов отвечает `-32601 Method not found`.

Полная схема метода, описания полей и коды ошибок — в контракте; читай его, если нужного поля нет в таблице:

```bash
pcurl @{topsrv_profile} https://app.topsrv.io/api/v1/rpc/openrpc.json -s | jq '.methods[] | select(.name | ascii_downcase == "weblog.top")'
pcurl @{topsrv_profile} https://app.topsrv.io/api/v1/rpc/openrpc.json -s | jq '.components.schemas.WebLogFilter'
```

## Метрики (PromQL)

- Хост — лейбл `instance`, его значение = `hostname` из `host.list`. Лейбл `hostname` есть только у `topsrv_host_info`: `{hostname="web-1"}` у остальных метрик ничего не находит.
- Ответ — `result.data.result[]`: `metric` — массив пар `{name, value}` (не map), `values[]` — точки `{timestamp, value}`, у instant-запроса ровно одна. Значение — строка, бывает `NaN`, `+Inf`.
- `queryRange`: `start` и `end` — unix-секунды, обязательны. Без `step` окно делится примерно на 1000 точек, шаг не меньше 1m. Больше 11000 точек — 400 `too_many_points`, увеличь `step`.
- Лейбла `project_id` в ответе нет.
- Пример `topsrv_disk_used_percent` из описания `metric.query` в контракте — такой метрики у агента нет, запрос вернёт пустой результат. Заполненность диска считается из `topsrv_filesystem_bytes` (рецепт ниже).

Каталог метрик агента и готовые рецепты — в репозитории агента; читай, когда нужной метрики нет в таблице:

```bash
pcurl https://raw.githubusercontent.com/vmkteam/topsrv/master/docs/metrics.md -s
pcurl https://raw.githubusercontent.com/vmkteam/topsrv/master/docs/promql-recipes.md -s
```

### Основные семейства

| Семейство | Метрики | Лейблы |
|-----------|---------|--------|
| Система | `topsrv_cpu_seconds_total`, `topsrv_cpu_cores`, `topsrv_memory_bytes`, `topsrv_load_average`, `topsrv_swap_bytes`, `topsrv_uptime_seconds` | cpu, mode; type (total/used/available/…); interval (1m/5m/15m) |
| Диск | `topsrv_filesystem_bytes`, `topsrv_filesystem_inodes`, `topsrv_disk_io_time_seconds_total`, `topsrv_disk_read_bytes_total`, `topsrv_disk_write_bytes_total` | mountpoint, device, fstype, type (total/used/free) |
| Сеть | `topsrv_network_bytes_total`, `topsrv_network_errors_total`, `topsrv_netstat_tcp_connections`, `topsrv_netstat_tcp_retransmits_total`, `topsrv_netstat_listening_ports` | interface, direction; state, direction, remote_scope; proto, port, scope, process |
| Процессы | `topsrv_process_cpu_seconds_total`, `topsrv_process_memory_bytes`, `topsrv_process_open_fds`, `topsrv_process_worst_fd_ratio` | group; type (rss/vms/swap) |
| PostgreSQL | `topsrv_pg_up`, `topsrv_pg_connections`, `topsrv_pg_max_connections`, `topsrv_pg_longest_transaction_seconds`, `topsrv_pg_blocked_backends`, `topsrv_pg_replication_lag_seconds`, `topsrv_pg_query_time_seconds_total`, `topsrv_pg_table_bloat_pct`, `topsrv_pg_wraparound_xid_age` | state; database, usename; client_addr; queryid, query; schema, table |
| Nginx | `topsrv_nginx_http_requests_total`, `topsrv_nginx_5xx_requests_total`, `topsrv_nginx_request_duration_seconds`, `topsrv_nginx_upstream_duration_seconds` | status, uri, ExtraLabels из конфига агента (например server_name) |
| Angie | `topsrv_angie_server_zone_responses_total`, `topsrv_angie_upstream_peer_state`, `topsrv_angie_upstream_peer_responses_total` | zone, code; upstream, peer |
| S.M.A.R.T. | `topsrv_smart_device_healthy`, `topsrv_smart_device_temperature_celsius`, `topsrv_smart_nvme_percentage_used` | device |
| SSL | `topsrv_ssl_certificate_expiry_seconds`, `topsrv_ssl_certificate_san_info` | path, cn, issuer; domain |
| Агент | `topsrv_host_info`, `topsrv_collector_scrape_duration_seconds`, `topsrv_collector_scrape_panics_total` | hostname, version; collector |

### Рецепты

```promql
# CPU, % (так считает host.summary)
sum by (instance) (rate(topsrv_cpu_seconds_total{mode!="idle"}[2m])) / on(instance) topsrv_cpu_cores * 100

# Память, %
topsrv_memory_bytes{type="used"} / on(instance) topsrv_memory_bytes{type="total"} * 100

# Заполненность файловых систем хоста, %
topsrv_filesystem_bytes{instance="{instance}",type="used",fstype!~"tmpfs|squashfs|devtmpfs|autofs"}
  / on(instance, mountpoint, device, fstype) topsrv_filesystem_bytes{type="total"} * 100

# Top-5 групп процессов по CPU, ядер
topk(5, sum by (instance, group) (rate(topsrv_process_cpu_seconds_total[5m])))

# PostgreSQL: занятость соединений, %; самая длинная транзакция, с; лаг реплик, с
sum by (instance) (topsrv_pg_connections) / on(instance) topsrv_pg_max_connections * 100
max by (instance, database) (topsrv_pg_longest_transaction_seconds)
max by (instance, client_addr) (topsrv_pg_replication_lag_seconds)

# PostgreSQL: top-10 запросов по времени выполнения
topk(10, sum by (instance, queryid, query) (rate(topsrv_pg_query_time_seconds_total[5m])))

# Nginx: RPS по статусам; p95 времени ответа, с
sum by (instance, status) (rate(topsrv_nginx_http_requests_total[5m]))
histogram_quantile(0.95, sum by (instance, le) (rate(topsrv_nginx_request_duration_seconds_bucket[5m])))

# TCP retransmit, % (норма до 1–2%)
100 * rate(topsrv_netstat_tcp_retransmits_total[5m]) / rate(topsrv_netstat_tcp_out_segs_total[5m])

# Дней до истечения сертификатов — те, что истекают в ближайшие 14 дней
(topsrv_ssl_certificate_expiry_seconds - time()) / 86400 < 14

# Порты, открытые наружу; нездоровые диски
topsrv_netstat_listening_ports{scope="public"}
topsrv_smart_device_healthy == 0
```

### Вызовы

```bash
# Instant
pcurl @{topsrv_profile} -sS https://app.topsrv.io/api/v1/rpc/ \
  -d '{"jsonrpc":"2.0","id":1,"method":"metric.query","params":{"query":"topsrv_load_average{instance=\"{instance}\",interval=\"1m\"}"}}'

# Range за последний час, шаг по умолчанию
pcurl @{topsrv_profile} -sS https://app.topsrv.io/api/v1/rpc/ -d "$(jq -nc \
  --arg q 'rate(topsrv_cpu_seconds_total{instance="{instance}",mode="user"}[5m])' \
  '{jsonrpc:"2.0",id:1,method:"metric.queryRange",params:{query:$q,start:((now|floor)-3600),end:(now|floor)}}')"

# Компактный вывод: лейблы и последнее значение серии
… | jq -c '.result.data.result[] | {m: (.metric | map("\(.name)=\(.value)") | join(",")), v: .values[-1].value}'
```

## Алерты

```bash
# Что горит сейчас: правила с открытым событием
pcurl @{topsrv_profile} -sS https://app.topsrv.io/api/v1/rpc/ -d '{"jsonrpc":"2.0","id":1,"method":"alert.rules"}' \
  | jq -c '.result[] | select(.currentState) | {code, severity, currentState, activeEventId, promql, threshold}'

# События: firing на хостах, имя которых содержит "web"
pcurl @{topsrv_profile} -sS https://app.topsrv.io/api/v1/rpc/ \
  -d '{"jsonrpc":"2.0","id":1,"method":"alert.list","params":{"state":"firing","host":"web","pageSize":50}}'
```

- `host` в `alert.list` — подстрока имени хоста. Хост события — в `labels[]`, элемент с `name` = `instance`.
- Закрытые вручную (dismissed) события `alert.list` не возвращает.
- `alert.rules[].promql` — выражение правила: прогони его через `metric.queryRange`, чтобы увидеть, как метрика подошла к порогу `threshold`.
- `alert.silence` — запись. Вызывай только по явной просьбе пользователя, показав matcher и окно до вызова. Matcher: `ruleCode`, `severity`, `instance`, `group` — хотя бы одно поле; `ruleCode` и `group` берутся из `alert.rules`. Окно — RFC3339, не длиннее 30 дней.

## Инвентарь и CVE

```bash
# Хосты с исправимыми уязвимостями
pcurl @{topsrv_profile} -sS https://app.topsrv.io/api/v1/rpc/ -d '{"jsonrpc":"2.0","id":1,"method":"inventory.hosts"}' \
  | jq -c '.result[] | select(.fixableCount > 0) | {hostname, os, osVersion, cveCount, fixableCount, rebootRequired, lastAuditAt}'

# Исправимые находки одного хоста
pcurl @{topsrv_profile} -sS https://app.topsrv.io/api/v1/rpc/ \
  -d '{"jsonrpc":"2.0","id":1,"method":"inventory.findings","params":{"hostname":"{instance}"}}' \
  | jq -c '.result[] | select(.fixedInVersion != "") | {package, version, fixedInVersion, cveId}'
```

- `cveCount: 0` сам по себе ничего не значит: без `lastAuditAt` аудит ещё не запускался.
- `rebootRequired` — установлено ядро новее работающего, фикс ядра вступит в силу после перезагрузки.
- Пустой `fixedInVersion` — исправленной версии пакета ещё нет.

## HTTP-логи: botlog и weblog

| | botlog | weblog |
|-|--------|--------|
| Что | только запросы ботов (UA из каталога агента) | весь HTTP-поток, включая людей |
| Хранение | 90 дней | 72 часа — это и максимальное окно запроса |
| Методы | `search` | `summary`, `top`, `networks`, `blockImpact`, `search` |

- `filter` обязателен: `{}` — последние 24 часа. Время — RFC3339; `from` включительно, `to` строго.
- Фильтры weblog — массивы: `host`, `serverName`, `path`, `pathTopSection`, `method`, `status`, `statusClass` (`2xx`…`5xx`, `dropped` — 444, 499 и коды выше 599), `remoteAddr` (IP или IPv4 CIDR), `asn`, `asnOrg`, `networkType`, `country`, `userAgent`, `botName`, `verifyState`, `requestId`, `visitorId`; скаляры `uaMatched`, `ipListed`, `requestTimeMinMs`.
- `weblog.top`: `groupBy` — host | hostPath | path | pathTopSection | remoteAddr | asn | userAgent | country | status | platform | appVersion | platformVersion | visitorId; `sortBy` — requests | bytes | effort | avgMs | p95Ms | c4xx | c5xx | firstSeen | lastSeen. `effort` — суммарное время обслуживания: сколько группа стоит бэкенду.
- Прежде чем советовать блокировку IP, UA или подсети — `weblog.blockImpact`: `visitorsOnlyHere` показывает, сколько живых посетителей потеряют доступ.
- `weblog.search` выгружай по времени, а не по offset: `sortDir: "asc"`, сдвигай `from` на время последнего события, дубли отбрасывай по `requestId`.
- `requestId` — id запроса, который nginx передал бэкенду: по нему событие находится в логах сервиса (`/loki`).
- `botlog.search` с `limit` больше 1000 отвечает 400, а не урезанной страницей. `verifyState: spoofed` — UA бота, но IP не подтверждает бота.
- Ответы: `weblog.top` — `result.rows[]`, значение группы в `value`, стоимость группы в `effortMs`; `weblog.search` — `result.events[]`, адрес с query string в `uri` (поля `path` у события нет), время — `requestTimeMs` и `upstreamMs`.
- Логи пишутся с момента, когда в агенте включили WebLogs, и окно бывает короче 72 часов. Первый срез — `weblog.top` с `groupBy: "host"` и `from` на 71 час назад (ровно 72 часа сервер считает как `72h1m0s` и отвечает 400): `firstSeen` покажет начало данных, строки — сайты проекта. Если сайтов несколько, фильтруй по `host`.
- Независимые срезы (summary, top по разным измерениям) отправляй одним батчем.
- Как читать 5xx: 502 за единицы миллисекунд при `upstreamMs: 0` — бэкенд не отвечал, обычно это рестарт при выкатке (сверь время с деплоями); 503/504 с `upstreamMs`, равным таймауту, — бэкенд не успел ответить.
- 499 и 405 на стриминговых эндпоинтах (MCP, SSE) — норма протокола: клиент закрыл поток, GET без поддержки SSE. Это не ошибки сайта.
- Живые посетители — примерно `uaMatched: false` вместе с `networkType: ["residential","mobile"]`.

```bash
# Кто нагружает сайт за последний час: AS по суммарному времени обслуживания
pcurl @{topsrv_profile} -sS https://app.topsrv.io/api/v1/rpc/ -d "$(jq -nc \
  '{jsonrpc:"2.0",id:1,method:"weblog.top",params:{groupBy:"asn",sortBy:"effort",filter:{from:(now-3600|todate)},limit:10}}')"

# Самые дорогие пути с 5xx за последний час
pcurl @{topsrv_profile} -sS https://app.topsrv.io/api/v1/rpc/ -d "$(jq -nc \
  '{jsonrpc:"2.0",id:1,method:"weblog.top",params:{groupBy:"path",sortBy:"effort",filter:{from:(now-3600|todate),statusClass:["5xx"]},limit:20}}')"

# Пулы скраперов: сети с десятками IP и малым числом User-Agent (uaPerIp сортирует по возрастанию)
pcurl @{topsrv_profile} -sS https://app.topsrv.io/api/v1/rpc/ \
  -d '{"jsonrpc":"2.0","id":1,"method":"weblog.networks","params":{"filter":{},"minIPs":20,"sortBy":"uaPerIp","limit":20}}'

# Кто запрашивает файл (llms.txt, robots.txt) и с каким ответом
pcurl @{topsrv_profile} -sS https://app.topsrv.io/api/v1/rpc/ \
  -d '{"jsonrpc":"2.0","id":1,"method":"weblog.top","params":{"groupBy":"userAgent","filter":{"path":["/llms.txt"]},"limit":50}}'

# Поддельные боты за сутки
pcurl @{topsrv_profile} -sS https://app.topsrv.io/api/v1/rpc/ \
  -d '{"jsonrpc":"2.0","id":1,"method":"botlog.search","params":{"filter":{"verifyState":["spoofed"]},"limit":100}}'
```

## Ошибки

Код и текст — в `error.code` и `error.message` ответа.

| Код | message | Что делать |
|-----|---------|------------|
| пустой 200 | — | в запросе нет `id` |
| 401 | `invalid_token`, `token_expired`, `token_revoked` | пользователь перевыпускает токен в UI и обновляет профиль; `pcurl add` сам не запускай |
| 403 | `insufficient_scope` | у токена нет scope метода; токен при этом валиден |
| 400 | `bad_query` | PromQL отклонён VictoriaMetrics, причина — в `error.data` |
| 400 | `invalid_range`, `too_many_points` | нет `start`/`end` или `end` не позже `start`; увеличь `step` |
| 400 | `period exceeds 72h…` | окно weblog шире 72 часов |
| 404 | `host_not_found` | хоста нет среди живых за 48 ч — сверь с `host.list` |
| 415 | Unsupported Media Type | в профиле нет `Content-Type: application/json` |
| 429 | `rate_limited` | 60 запросов в минуту на токен, burst 20; подожди `Retry-After` |
| -32601 | Method not found | опечатка в имени метода или namespace не зарегистрирован |
| -32700 | Parse error | тело не JSON, например `-d @-` |

## Прямые ссылки

```
https://app.topsrv.io/projects/{slug}/                 # хосты
https://app.topsrv.io/projects/{slug}/{instance}/      # хост
https://app.topsrv.io/projects/{slug}/alerts/
https://app.topsrv.io/projects/{slug}/inventory/
https://app.topsrv.io/projects/{slug}/web-logs/
https://app.topsrv.io/projects/{slug}/bot-logs/
```
