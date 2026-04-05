---
name: zenrpc
description: "Zenrpc — справочник по JSON-RPC 2.0 серверу для Go. Используй при создании и редактировании RPC-сервисов."
---

# Zenrpc — справочник по использованию

Ты — эксперт по zenrpc (https://github.com/vmkteam/zenrpc).

## Обзор

Zenrpc — JSON-RPC 2.0 сервер для Go, использующий `go generate` вместо рефлексии.
Поддерживает SMD (Service Mapping Description) и OpenRPC спецификации.

## Экосистема

| Компонент | Назначение |
|-----------|-----------|
| `vmkteam/zenrpc/v2` | Основная библиотека (сервер, генератор) |
| `vmkteam/zenrpc-middleware` | Middleware: логирование, метрики, Sentry |
| `vmkteam/rpcgen/v2` | Генерация клиентов (Go/TS/PHP/Swift/Kotlin/Dart/OpenRPC) |
| SMDBox | Swagger-like браузер JSON-RPC API (совместим с SMD) |
| Brokersrv | NATS как транспорт для zenrpc |
| Rpcdiff | Diff между старым и новым OpenRPC schema |

## Транспорты

- **HTTP** — основной (`echo.WrapHandler(rpc)`)
- **WebSocket** — встроенная поддержка
- **NATS** — через brokersrv

## Генерация кода

```go
// в server.go
//go:generate go tool zenrpc
```

Go tool подключен в go.mod:
```go
tool github.com/vmkteam/zenrpc/v2/zenrpc
```

```bash
make generate   # запускает go generate для всех RPC-пакетов
```

**ВАЖНО:** После любых изменений в API (методы, параметры, аннотации) — `make generate`.

## Определение сервиса

Сервис — Go-структура с встроенным `zenrpc.Service`:

```go
// RPC-сервис
type ReviewService struct {
    rm *reviewer.ReviewManager
    zenrpc.Service
}

// VT-сервис (дополнительно embedlog.Logger)
type ProjectService struct {
    zenrpc.Service
    embedlog.Logger
    projectRepo db.ProjectRepo
}
```

## Сигнатуры методов

```go
func (Service) Method([args]) (<value>, <error>)
func (Service) Method([args]) <value>
func (Service) Method([args]) <error>
func (Service) Method([args])
```

- Первый аргумент может быть `context.Context` (рекомендуется)
- Return values могут быть указателями
- Ошибки: `error` или `*zenrpc.Error`

## Аннотации (magic comments)

```go
// GetByID returns review details.
//
//zenrpc:reviewId Review ID
//zenrpc:return Review
//zenrpc:500 Internal Error
//zenrpc:404 Not Found
func (s ReviewService) GetByID(ctx context.Context, reviewId int) (*Review, error) {
    // ...
}
```

| Формат | Назначение |
|--------|-----------|
| `//zenrpc:<param> Description` | Описание параметра |
| `//zenrpc:<param>=<default> Description` | Параметр со значением по умолчанию |
| `//zenrpc:<httpCode> Description` | Код ошибки |
| `//zenrpc:return Description` | Описание возврата |

## Обработка ошибок

```go
// RPC-слой
var (
    ErrInternal   = zenrpc.NewStringError(http.StatusInternalServerError, "internal error")
    ErrNotFound   = zenrpc.NewStringError(http.StatusNotFound, "not found")
    ErrBadRequest = zenrpc.NewStringError(http.StatusBadRequest, "bad request")
)

func newInternalError(err error) *zenrpc.Error {
    return zenrpc.NewError(http.StatusInternalServerError, err)
}

// VT-слой
func httpAsRPCError(code int) *zenrpc.Error {
    return zenrpc.NewStringError(code, http.StatusText(code))
}

var (
    ErrUnauthorized = httpAsRPCError(http.StatusUnauthorized)
    ErrForbidden    = httpAsRPCError(http.StatusForbidden)
    ErrNotFound     = httpAsRPCError(http.StatusNotFound)
    ErrInternal     = httpAsRPCError(http.StatusInternalServerError)
)
```

## Настройка сервера (server.go)

```go
//go:generate go tool zenrpc

func New(dbo db.DB, logger embedlog.Logger, isDevel bool) *zenrpc.Server {
    rpc := zenrpc.NewServer(zenrpc.Options{
        ExposeSMD: true,
        AllowCORS: true,
    })

    rpc.Use(
        zm.WithDevel(isDevel),
        zm.WithHeaders(),
        zm.WithSentry(zm.DefaultServerName),
        zm.WithNoCancelContext(),
        zm.WithMetrics(zm.DefaultServerName),
        zm.WithTiming(isDevel, allowDebugFn()),
        zm.WithSQLLogger(dbo.DB, isDevel, allowDebugFn(), allowDebugFn()),
        zm.WithSLog(logger.Print, zm.DefaultServerName, nil),
        zm.WithErrorSLog(logger.Error, zm.DefaultServerName, nil),
    )

    rpc.RegisterAll(map[string]zenrpc.Invoker{
        "review": NewReviewService(dbo),
    })

    return rpc
}
```

## Middleware (zenrpc-middleware)

Импорт: `zm "github.com/vmkteam/zenrpc-middleware"`

| Middleware | Что делает |
|-----------|-----------|
| `zm.WithDevel(isDevel)` | Устанавливает флаг dev-режима в контексте |
| `zm.WithHeaders()` | Захватывает User-Agent (2048), Platform (64), Version (64), X-Country (16) в контекст |
| `zm.WithSentry(serverName)` | Sentry scope: params, duration, IP, platform, version, method |
| `zm.WithNoCancelContext()` | Подавляет Cancel в контексте (нужно для go-pg) |
| `zm.WithMetrics(serverName)` | Prometheus: `app_rpc_error_requests_total`, `app_rpc_responses_duration_seconds` (labels: method, code, platform, version, server) |
| `zm.WithTiming(isDevel, allowDebugFn)` | DurationLocal в Response extensions (ms) |
| `zm.WithSQLLogger(db, isDevel, allow1, allow2)` | SQL/DurationSQL в response extensions |
| `zm.WithSLog(printFn, serverName, nil)` | Structured logging (slog.InfoContext) |
| `zm.WithErrorSLog(errorFn, serverName, nil)` | Логирование ошибок (code==500 или <0), отправка в Sentry |
| `zm.WithAPILogger(printFn, serverName)` | Legacy: Printf-style логирование (IP, platform, method, duration, params, UA) |

### Кастомный middleware (аутентификация)

```go
func authMiddleware(commonRepo *db.CommonRepo, logger embedlog.Logger) zenrpc.MiddlewareFunc {
    return func(h zenrpc.InvokeFunc) zenrpc.InvokeFunc {
        return func(ctx context.Context, method string, params json.RawMessage) zenrpc.Response {
            ns := zenrpc.NamespaceFromContext(ctx)
            if ns == NSAuth && method == RPC.AuthService.Login {
                return h(ctx, method, params)
            }
            // проверка auth header...
            return h(context.WithValue(ctx, userKey, dbu), method, params)
        }
    }
}
```

### Доступ к контексту

```go
req, ok := zenrpc.RequestFromContext(ctx)   // HTTP-запрос
ns := zenrpc.NamespaceFromContext(ctx)       // namespace
id := zenrpc.IDFromContext(ctx)              // ID запроса
```

## Паттерны VT-сервисов (CRUD)

Стандартный набор для каждой сущности: Count, Get, GetByID, Add, Update, Delete, Validate.

Приватные хелперы: `byID`, `dbSort`, `isValid`.

### Три типа моделей

1. **Entity** — полная модель (GetByID, Add, Update)
2. **EntitySearch** — фильтры с `ToDB()` конвертером
3. **EntitySummary** — краткая для списков

### ViewOps — пагинация и сортировка

```go
type ViewOps struct {
    Page       int    `json:"page"`
    PageSize   int    `json:"pageSize"`   // max 500
    SortColumn string `json:"sortColumn"`
    SortDesc   bool   `json:"sortDesc"`
}
```

### Валидация (только VT)

```go
type Validator struct {
    fields []FieldError
    err    error
}
```

Теги: `validate:"required"`, `validate:"required,max=255"`, `validate:"required,status"`, `validate:"required,alias"`.

## Сгенерированные файлы

Файлы `*_zenrpc.go` содержат:
- `Invoke()` — маршрутизация JSON-RPC вызовов
- SMD-описания для каждого сервиса
- Константы имён методов (`RPC.ServiceName.MethodName`)
- Автоматический парсинг параметров из JSON

**НЕ РЕДАКТИРУЙ** `*_zenrpc.go` вручную.

## JSON-RPC 2.0

Поддерживает:
- Одиночные и batch-запросы
- Нотификации (без ответа)
- Именованные и позиционные параметры
- Значения параметров по умолчанию
- SMD-схема (`ExposeSMD: true`)

## Типичные сценарии

### Добавить новый метод
1. Добавить метод с zenrpc-аннотациями
2. Добавить модели если нужно
3. `make generate`

### Добавить новый CRUD-сервис в VT
1. Namespace-константа в server.go
2. Файл модели: Entity, EntitySearch, EntitySummary
3. Файл конвертера: NewEntity, NewEntitySummary
4. Файл сервиса: Count, Get, GetByID, Add, Update, Delete, Validate
5. Зарегистрировать в server.go
6. `make generate`
