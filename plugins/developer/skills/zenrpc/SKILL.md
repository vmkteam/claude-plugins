---
name: zenrpc
description: "Zenrpc — справочник по JSON-RPC 2.0 серверу для Go. Используй при создании и редактировании RPC-сервисов."
---

# Zenrpc

- Upstream: https://github.com/vmkteam/zenrpc (v2)
- Middleware: https://github.com/vmkteam/zenrpc-middleware (импорт `zm`)
- Clients: https://github.com/vmkteam/rpcgen (v2, см. /rpcgen)
- JSON-RPC 2.0, codegen через `go generate` (не reflection), SMD + OpenRPC
- Транспорты: HTTP (`echo.WrapHandler(rpc)`), WebSocket, NATS (brokersrv)
- Экосистема: SMDBox (браузер API), rpcdiff (diff OpenRPC)

## Codegen

```go
//go:generate go tool zenrpc
```

`go.mod` содержит `tool github.com/vmkteam/zenrpc/v2/zenrpc`. `make generate` — обязательно после любых изменений в API/моделях/аннотациях. Файлы `*_zenrpc.go` не редактировать.

## Сервис

Встраивание `zenrpc.Service`; VT-сервисы дополнительно встраивают `embedlog.Logger`:

```go
type ReviewService struct {
    rm *reviewer.ReviewManager
    zenrpc.Service
}

type ProjectService struct {
    zenrpc.Service
    embedlog.Logger
    projectRepo db.ProjectRepo
}
```

Сигнатура метода: `func (Service) Method([ctx,] [args]) (<value>, <error>)` — любой return опционален, value может быть pointer, error = `error | *zenrpc.Error`.

## Аннотации (magic comments)

```go
// GetByID returns review details.
//
//zenrpc:reviewId Review ID
//zenrpc:return Review
//zenrpc:500 Internal Error
//zenrpc:404 Not Found
func (s ReviewService) GetByID(ctx context.Context, reviewId int) (*Review, error) {
```

- `//zenrpc:<param> Description` — описание параметра
- `//zenrpc:<param>=<default> Description` — default value
- `//zenrpc:<httpCode> Description` — код ошибки
- `//zenrpc:return Description` — описание возврата

## Ошибки

RPC-слой использует `zenrpc.NewStringError`, для wrap — `zenrpc.NewError`:

```go
var (
    ErrInternal   = zenrpc.NewStringError(http.StatusInternalServerError, "internal error")
    ErrNotFound   = zenrpc.NewStringError(http.StatusNotFound, "not found")
    ErrBadRequest = zenrpc.NewStringError(http.StatusBadRequest, "bad request")
)
func newInternalError(err error) *zenrpc.Error {
    return zenrpc.NewError(http.StatusInternalServerError, err)
}
```

VT-слой: хелпер `httpAsRPCError(code int) *zenrpc.Error` → `ErrUnauthorized/Forbidden/NotFound/Internal`.

## Server (канонический шаблон)

```go
//go:generate go tool zenrpc

func New(dbo db.DB, logger embedlog.Logger, isDevel bool) *zenrpc.Server {
    rpc := zenrpc.NewServer(zenrpc.Options{ExposeSMD: true, AllowCORS: true})
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

## Middleware (`zm`)

| MW | Назначение / gotcha |
|----|---------------------|
| `WithDevel(isDevel)` | dev-флаг в ctx |
| `WithHeaders()` | UA(2048)/Platform(64)/Version(64)/X-Country(16) в ctx |
| `WithSentry(serverName)` | scope: params, duration, IP, platform, version, method |
| `WithNoCancelContext()` | **обязателен для go-pg**: подавляет ctx.Cancel |
| `WithMetrics(serverName)` | `app_rpc_error_requests_total`, `app_rpc_responses_duration_seconds` — labels: method, code, platform, version, server |
| `WithTiming(isDevel, allowFn)` | `DurationLocal` в response extensions (ms) |
| `WithSQLLogger(db, isDevel, allow1, allow2)` | SQL/DurationSQL в extensions |
| `WithSLog(logger.Print, name, nil)` | slog.InfoContext |
| `WithErrorSLog(logger.Error, name, nil)` | code==500 или <0 → лог + Sentry |
| `WithAPILogger(printFn, name)` | legacy Printf-style |

### Кастомный auth-middleware

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

### Context accessors

```go
req, ok := zenrpc.RequestFromContext(ctx)  // *http.Request
ns := zenrpc.NamespaceFromContext(ctx)     // namespace
id := zenrpc.IDFromContext(ctx)            // request id
```

## Сгенерированные файлы

`*_zenrpc.go`: `Invoke()` (роутинг), SMD, константы `RPC.ServiceName.MethodName`, парсинг params. **Не редактировать вручную**.

## VT-конвенции (CRUD)

Стандартный набор на сущность: Count, Get, GetByID, Add, Update, Delete, Validate. Приватные хелперы: `byID`, `dbSort`, `isValid`.

Три типа моделей: **Entity** (полная), **EntitySearch** (фильтры + `ToDB()`), **EntitySummary** (для списков).

`ViewOps{Page, PageSize (max 500), SortColumn, SortDesc}` — пагинация/сортировка.

Валидация (только VT): `Validator{fields []FieldError; err error}`; теги `validate:"required,max=255,status,alias"`.

## Чеклисты

**Новый метод:** аннотации → модели → `make generate`.

**Новый CRUD VT-сервис:** namespace-константа → модели (Entity/Search/Summary) → конвертеры (`NewEntity`, `NewEntitySummary`) → сервис (Count/Get/GetByID/Add/Update/Delete/Validate) → регистрация в `server.go` → `make generate`.
