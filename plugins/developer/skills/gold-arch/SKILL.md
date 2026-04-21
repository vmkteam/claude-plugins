---
name: gold-arch
description: "Gold Architecture — справочник по проектированию Go-сервисов. Используй при создании новых сервисов и добавлении слоёв."
---

# Gold Architecture — Go API-сервисы vmkteam

Шаблон: [gold-apisrv](https://github.com/vmkteam/gold-apisrv). Философия: [vmkteam.dev](https://vmkteam.dev).

JSON-RPC 2.0 поверх echo. Простота важнее абстракций. **Без интерфейсов** кроме как в domain (если нужно).

> **Слоистость — осознанный выбор vmkteam, а не универсальная Go-идиома.** Flat packages идиоматичнее в малых и средних Go-проектах. Мы используем слоистую (db → domain → rpc) потому что: (1) типичный сервис — CRUD + фоновые процессоры + несколько API-endpoint'ов (public/vt/debug), (2) явные конвертеры между слоями убирают риск db-моделей в JSON, (3) кодогенерация (mfd/colgen/zenrpc) лучше ложится на чёткие границы слоёв. Вне vmkteam-контекста эта структура может быть избыточна — не применяй её слепо.

## Слои и зависимости

```
pkg/rpc, pkg/vt, pkg/debug     ← API: свои модели, конвертеры, zenrpc
         ↓
pkg/<projectname>              ← Domain: Manager, Processor, свои модели
         ↓
pkg/db                         ← ORM-модели, EntityRepo, OpFunc
         ↓
PostgreSQL
```

Зависимости строго вниз. API никогда не импортирует db-модели в JSON — только через конвертер `NewEntity(db *db.Entity) *Entity` в том же слое (см. `/colgen`).

## Именование пакетов (vmkteam-конвенция)

| Так | Не так |
|---|---|
| `db` | `repository` |
| `rpc` | `handlers`, `api` |
| `<projectname>` | `domain`, `logic`, `service` |
| `vt` / `debug` | `admin`, `backoffice` |

## Структура

```
cmd/<srvname>/main.go
pkg/app/                  App struct, DI, lifecycle, routing, config, metrics
pkg/db/                   generated ORM
pkg/<projectname>/        domain (+подпакеты по bounded contexts: auth/, chat/...)
pkg/rpc/                  public API, файлы по доменам (auth.go, chat.go — не один большой)
pkg/vt/ | pkg/debug/      admin API, CRUD + Validator
pkg/client/<othersrv>/    rpcgen-клиенты чужих сервисов, push, sms, geoip
cfg/local.toml.dist
docs/*.pgd | *.pdd        схема БД
```

В `pkg/` — только значимые пакеты. Интеграции — всегда в `pkg/client/`.

## DB слой (генерируется mfd-generator)

ORM-модель:
```go
type User struct {
    tableName struct{} `pg:"users,alias:t,discard_unknown_columns"`
    ID       int    `pg:"userId,pk"`
    Login    string `pg:"login,use_zero"`
}
```

EntityRepo методы: `EntityByID`, `EntitiesByFilters`, `CountEntities`, `AddEntity`, `UpdateEntity`, `DeleteEntity` — все с `ops ...OpFunc`.

OpFunc композиция: `WithSort`, `WithColumns`, `WithRelations`, `EnabledOnly`.

## Domain слой

**Нужен когда:** бизнес-логика сложнее CRUD, фоновый процессор, несколько API-слоёв делят логику.
**НЕ нужен когда:** простой CRUD — VT работает напрямую с db.

Паттерны:
- `Manager` — синхронные операции (`Create`, `Cancel`...)
- `Processor` — фоновые горутины: `Run(ctx)` блокирующий + `ProcessX(ctx, ...)`.

Для больших проектов — подпакеты по bounded contexts (`auth/`, `chat/`, `subscription/`, `match/`), главный `app.go` связывает.

## API слой

- Свои модели (не db-структуры в JSON)
- Конвертеры через `/colgen`
- `//go:generate go tool zenrpc` в server.go

**VT CRUD — 7 методов:** Count, Get, GetByID, Add, Update, Delete, Validate + хелперы `byID`, `dbSort`, `isValid`.

**Три типа моделей VT:** `Entity` (полная), `EntitySearch` (фильтры), `EntitySummary` (для списков).

## Масштабирование

Несколько zenrpc-серверов на разных endpoint'ах — свои middleware/namespace/authz:
```go
type App struct {
    srv         *zenrpc.Server  // /v1/rpc/
    srvDebug    *zenrpc.Server  // /v1/debug/
    srvInternal *zenrpc.Server  // server-to-server
}
```

Rpcgen клиенты прямо с endpoint'а (для публичных API):
```go
a.echo.Any("/v1/rpc/api.ts",      appkit.EchoHandlerFunc(rpcgen.Handler(gen.TSClient(typeMapper))))
a.echo.Any("/v1/rpc/api.go",      appkit.EchoHandlerFunc(rpcgen.Handler(gen.GoClient(settings))))
a.echo.Any("/v1/rpc/openrpc.json",appkit.EchoHandlerFunc(rpcgen.Handler(gen.OpenRPC("name", rpcUrl))))
```

## Стек

HTTP: `labstack/echo`. RPC: `vmkteam/zenrpc/v2` + `zenrpc-middleware`. ORM: `go-pg/pg/v10`. Log: `vmkteam/embedlog` (slog). Metrics: `prometheus/client_golang`. Errors: `sentry-go`. Validate: `go-playground/validator/v10`. Cron: `vmkteam/cron`. Utils: `vmkteam/appkit`. Config: TOML. Codegen: zenrpc, mfd-generator, rpcgen, colgen.

## Чеклист нового сервиса

1. `.pgd` схема → 2. SQL + `pkg/db` → 3. решить про domain → 4. RPC/VT сервисы → 5. server.go (middleware, регистрация) → 6. `make generate` → 7. TOML config, main.go, app.go.

## Антипаттерны

- db-модели в JSON
- интерфейсы без необходимости
- пакеты `util`, `service`, `handlers`, `domain`
- пропуск конвертеров между слоями
- domain-слой ради простого CRUD
- global state вместо DI через конструкторы
