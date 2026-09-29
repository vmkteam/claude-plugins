---
name: security
description: "Security — чеклист безопасности Go-сервисов: валидация входа, секреты, auth, CVE-зависимости. Используй при правке auth-middleware, обработке user input, внешних вызовах, или как чеклист в /go-review."
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
        return nil, newInternalError(err)
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

`zenrpc.NewError(code, err)` кладёт `err.Error()` в `message` ответа. Для кода 500 (и отрицательных) это безопасно только благодаря middleware: `zm.WithErrorSLog` (legacy — `zm.WithErrorLogger`) логирует такую ошибку, отправляет её в Sentry и заменяет `message` на `"Internal error"`. Для остальных кодов маскировки нет.

**Хорошо** — внутренняя ошибка: причина уходит в Sentry, клиент видит `"Internal error"`:
```go
func newInternalError(err error) *zenrpc.Error {
    return zenrpc.NewError(http.StatusInternalServerError, err)
}

return nil, newInternalError(err)
```
Работает, только если `zm.WithErrorSLog` есть в `rpc.Use(...)` в `server.go` — без него клиент получит текст ошибки.

**Хорошо** — клиентская ошибка с фиксированным текстом:
```go
var ErrNotFound = zenrpc.NewStringError(http.StatusNotFound, "not found")
```

**Плохо** — `NewError` с кодом 4xx: текст внутренней ошибки уходит клиенту как есть:
```go
return nil, zenrpc.NewError(http.StatusBadRequest, err)
// Клиент увидит: {"error":{"code":400,"message":"pq: relation \"orders\" does not exist"}}
```

**Плохо** — `zenrpc.NewStringError(500, "internal error")` вместо `newInternalError(err)`: клиенту безопасно, но в Sentry уходит строка без причины, и диагностировать нечем.

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
| **Errors** | 4xx — `NewStringError` с фиксированным текстом; 500 — `newInternalError(err)`, и в цепочке middleware есть `zm.WithErrorSLog` |
| **Logging** | Пароли/токены не в параметрах логируемых методов |
| **Secrets** | `cfg/local.toml` в `.gitignore`, нет hardcoded credentials |
| **CORS** | Ограничен в production |
