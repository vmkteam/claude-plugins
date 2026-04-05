---
name: security
description: "Security — справочник по безопасности vmkteam Go-сервисов. Используется при code review и разработке."
---

# Security — безопасность vmkteam Go-сервисов

Справочник по безопасности для vmkteam-стека: JSON-RPC API, go-pg, zenrpc, auth middleware. Используется автоматически при code review (/go-review) и разработке (/solve).

## Инструменты

| Инструмент | Что ищет | Команда |
|-----------|----------|---------|
| `gosec` | SQL injection, hardcoded credentials, weak crypto, command injection | `gosec ./...` |
| `govulncheck` | Уязвимости в зависимостях (только реально используемые функции) | `govulncheck ./...` |
| `gitleaks` | API keys, tokens, passwords в коде и git-истории | `gitleaks detect --source .` |
| `trivy` | Уязвимости в Docker-образах | CI only |

## SQL Injection

Главная точка риска — `_repo_ext.go` (кастомные запросы).

**Плохо** — пользовательский ввод в raw SQL:
```go
// УЯЗВИМО: searchText попадает в SQL напрямую
func (r OrderRepo) SearchOrders(ctx context.Context, searchText string) ([]Order, error) {
    var orders []Order
    _, err := r.db.Query(&orders,
        "SELECT * FROM orders WHERE title LIKE '%"+searchText+"%'", nil)
    return orders, err
}
```

**Хорошо** — параметризованный запрос через go-pg:
```go
func (r OrderRepo) SearchOrders(ctx context.Context, searchText string) ([]Order, error) {
    var orders []Order
    err := r.db.Model(&orders).
        Where("title ILIKE ?", "%"+searchText+"%").
        Select()
    return orders, err
}
```

**Хорошо** — если нужен raw SQL, использовать `pg.SafeQuery`:
```go
q := r.db.Model(&orders)
q = q.Where("? ILIKE ?", pg.Ident("title"), "%"+searchText+"%")
```

**Правило**: go-pg ORM экранирует автоматически. Опасность только в `Query()` с конкатенацией строк.

## Аутентификация и авторизация

### Auth middleware (типичная ошибка — IDOR)

Middleware проверяет **аутентификацию** (есть ли валидный токен), но **не авторизацию** (может ли этот пользователь делать это действие).

**Плохо** — middleware пропустил, но метод не проверяет ownership:
```go
func (s OrderService) GetByID(ctx context.Context, id int) (*Order, error) {
    // Любой авторизованный пользователь может получить любой заказ
    return s.repo.OrderByID(ctx, id)
}
```

**Хорошо** — проверка ownership:
```go
func (s OrderService) GetByID(ctx context.Context, id int) (*Order, error) {
    user := UserFromContext(ctx)
    order, err := s.repo.OrderByID(ctx, id)
    if err != nil {
        return nil, InternalError(err)
    }
    if order == nil {
        return nil, ErrNotFound
    }
    if order.UserID != user.ID {
        return nil, ErrForbidden
    }
    return NewOrder(order), nil
}
```

### Auth whitelist

В `server.go` middleware пропускает определённые методы без авторизации. Whitelist должен быть **минимальным**:

```go
// Только auth.Login не требует токен
if ns == NSAuth && method == RPC.AuthService.Login {
    return h(ctx, method, params)
}
```

## Error Information Leakage

**Плохо** — внутренняя ошибка утекает клиенту:
```go
// zenrpc.NewError передаёт err.Error() клиенту в data
return nil, zenrpc.NewError(500, err)
// Клиент увидит: {"error":{"code":500,"message":"pq: relation \"orders\" does not exist"}}
```

**Хорошо** — generic message клиенту, детали в Sentry:
```go
// zenrpc.NewStringError — клиент видит только message
return nil, zenrpc.NewStringError(500, "internal error")
// Клиент увидит: {"error":{"code":500,"message":"internal error"}}
// Настоящая ошибка уйдёт в Sentry через WithSentry middleware
```

**Хелпер** — err в Sentry, generic клиенту:
```go
func newInternalError(err error) *zenrpc.Error {
    return zenrpc.NewError(500, err)
    // WithErrorSLog middleware залогирует и отправит в Sentry
    // Клиент получит code=500 без деталей
}
```

## Sensitive Data in Logs

zenrpc-middleware (`WithSLog`, `WithAPILogger`) логирует параметры запросов. Если метод принимает пароль — он попадёт в логи.

**Решение**: не передавать секреты как RPC-параметры, или фильтровать в middleware.

## JSON-RPC специфика

- Все методы через один POST endpoint (`/rpc/`) — стандартные WAF-правила для REST не работают
- Rate limiting на уровне reverse proxy (traefik/nginx) — по IP, не по методу
- CORS: `AllowOrigins: []string{"*"}` допустим в dev, но в production ограничивать доменами

## Чеклист для code review

| Категория | Проверить |
|-----------|----------|
| **SQL** | Нет конкатенации строк в `_repo_ext.go` |
| **Auth** | Whitelist методов минимальный |
| **Authz** | Проверка ownership/прав внутри методов (не только middleware) |
| **Validation** | Все входы через `go-playground/validator`, max длины строк |
| **Errors** | `NewStringError` для клиента, `NewError` только через middleware |
| **Logging** | Пароли/токены не в параметрах логируемых методов |
| **Secrets** | `cfg/local.toml` в `.gitignore`, нет hardcoded credentials |
| **CORS** | Ограничен в production |
