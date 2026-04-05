---
name: api-health
description: "API Health — проверка здоровья JSON-RPC сервисов (zenrpc), SMD, тайминги."
---

# API Health — проверка JSON-RPC сервисов

Проверка здоровья API и тестовые запросы к JSON-RPC (zenrpc) сервисам.

## Подключение

```
Profile: @{api_prod_profile} (production), @{api_dev_profile} (staging)
API type: JSON-RPC 2.0 (zenrpc)
RPC endpoint: определяется при онбординге (может быть /rpc/, /v1/rpc/, /v3/rpc/ и т.д.)
```

> **ВАЖНО:**
> - `/status` и `/healthcheck` обычно скрыты за firewall, недоступны снаружи
> - SMD (GET на RPC endpoint) может не работать через reverse proxy (фронтенд перехватывает GET)
> - RPC endpoint может быть версионирован: `/v1/rpc/`, `/v3/rpc/` — уточнять при онбординге

## Команды pcurl

### JSON-RPC запрос
```bash
pcurl @{profile} https://{host}/{rpc_endpoint} -s -L -X POST \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"{namespace.method}","params":{params},"id":1}'
```

### С таймингами
```bash
pcurl @{profile} https://{host}/{rpc_endpoint} -s -L -X POST \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"{namespace.method}","params":{params},"id":1}' \
  -w '\n---\nHTTP %{http_code} | Time: %{time_total}s | TTFB: %{time_starttransfer}s | Size: %{size_download}b\n'
```

### Только тайминги
```bash
pcurl @{profile} https://{host}/{rpc_endpoint} -s -o /dev/null -X POST \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"{namespace.method}","params":{params},"id":1}' \
  -w 'HTTP %{http_code} | Total: %{time_total}s | TTFB: %{time_starttransfer}s\n'
```

### SMD (Service Mapping Description)
```bash
# SMD доступен через ?smd query parameter
pcurl @{profile} 'https://{host}/{rpc_endpoint}?smd' -s -L

# SMDBox UI (документация в браузере)
# https://{host}/{rpc_endpoint}doc/
```

## JSON-RPC 2.0 формат

Запрос:
```json
{"jsonrpc": "2.0", "method": "namespace.method", "params": {"key": "value"}, "id": 1}
```

Успех:
```json
{"jsonrpc": "2.0", "result": {...}, "id": 1}
```

Ошибка (HTTP 200, но error в body!):
```json
{"jsonrpc": "2.0", "error": {"code": -32600, "message": "Invalid Request"}, "id": 1}
```

### Стандартные коды ошибок zenrpc
- `-32700` — Parse error
- `-32600` — Invalid Request
- `-32601` — Method not found
- `-32602` — Invalid params
- `-32603` — Internal error
- `400` — Bad Request (валидация)
- `401` — Unauthorized (Invalid token)
- `403` — Forbidden
- `404` — Not Found
- `500` — Internal Error
