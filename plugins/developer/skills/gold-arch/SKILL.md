---
name: gold-arch
description: "Gold Architecture — справочник по проектированию Go-сервисов. Используй при создании новых сервисов и добавлении слоёв."
---

# Gold Architecture — справочник по проектированию Go-сервисов

Ты — эксперт по архитектуре Go API-сервисов на основе gold-apisrv (vmkteam) и Simple Architecture (vmkteam.dev). Используй это руководство при проектировании новых сервисов, добавлении слоёв, сервисов и методов.

## Философия

Гибрид чистой и гексагональной архитектуры поверх JSON-RPC 2.0. Простой код важнее абстрактного. Поголовное отсутствие интерфейсов (кроме domain-слоя если нужно). Каждый слой знает только о слое ниже.

## Трёхслойная архитектура

```
API слой (pkg/rpc, pkg/vt, pkg/debug)   ← свои модели, конвертеры
    ↓ вызывает
Domain слой (pkg/<projectname>)          ← бизнес-логика, свои модели, менеджеры
    ↓ вызывает
DB слой (pkg/db)                         ← ORM-модели, репозитории, фильтры
    ↓
PostgreSQL
```

**Направление зависимостей строго сверху вниз.**

## Структура пакетов

```
cmd/<srvname>/main.go           # точка входа
pkg/app/                        # App struct, DI, lifecycle, routing, config, metrics
pkg/db/                         # ORM-модели, *Search, EntityRepo, OpFunc
pkg/<projectname>/              # Domain: Manager, Processor, доменные модели
pkg/<projectname>/auth/         # (опционально) подпакеты domain по bounded contexts
pkg/rpc/                        # Public API: zenrpc сервисы, свои модели
pkg/rpc/auth.go, chat.go        # файлы по доменам (не один большой файл)
pkg/vt/ или pkg/debug/          # Admin API: CRUD-сервисы, Validator
pkg/client/<othersrv>/          # rpcgen-клиенты других сервисов
cfg/local.toml.dist             # шаблон конфига
docs/*.pgd / *.pdd              # схема БД
```

### Именование пакетов

| Правильно | Неправильно |
|-----------|-------------|
| `db` | `repository` |
| `rpc` | `handlers`, `api` |
| `<projectname>` | `domain`, `logic`, `service` |
| `vt` / `debug` | `admin`, `backoffice` |

## DB слой (`pkg/db/`)

### ORM-модели (generated)
```go
type User struct {
    tableName struct{} `pg:"users,alias:t,discard_unknown_columns"`
    ID        int       `pg:"userId,pk"`
    Login     string    `pg:"login,use_zero"`
    StatusID  int       `pg:"statusId,use_zero"`
}
```

### EntityRepo (generated)
```go
func (r EntityRepo) EntityByID(ctx, id, ops ...OpFunc) (*Entity, error)
func (r EntityRepo) EntitiesByFilters(ctx, search, pager, ops ...OpFunc) ([]Entity, error)
func (r EntityRepo) CountEntities(ctx, search, ops ...OpFunc) (int, error)
func (r EntityRepo) AddEntity(ctx, entity, ops ...OpFunc) (*Entity, error)
func (r EntityRepo) UpdateEntity(ctx, entity, ops ...OpFunc) (bool, error)
func (r EntityRepo) DeleteEntity(ctx, id) (bool, error)
```

### OpFunc — композиция запросов
```go
type OpFunc func(query *orm.Query)
func WithSort(fields ...SortField) OpFunc
func WithColumns(cols ...string) OpFunc
func WithRelations(rels ...string) OpFunc
func EnabledOnly() OpFunc
```

## Domain слой

### Когда нужен
- Бизнес-логика сложнее CRUD
- Фоновый процессор
- Несколько API-слоёв используют одну логику

### Когда НЕ нужен
- Простой CRUD (VT работает напрямую с db)

### Паттерн Manager
```go
type OrderManager struct {
    orderRepo    db.OrderRepo
    pharmacyRepo db.PharmacyRepo
}
func (m *OrderManager) Create(ctx, order *db.Order) (*db.Order, error)
func (m *OrderManager) Cancel(ctx, orderId int) (*db.Order, error)
```

### Паттерн Processor (фоновые горутины)
```go
func (p *Processor) Run(ctx context.Context)            // блокирующий
func (p *Processor) ProcessOrder(ctx, order *db.Order) error
```

### Развитый domain — подпакеты

Для сложных проектов domain-слой разбивается на подпакеты по bounded contexts:

```
pkg/<projectname>/
├── app.go              # главный Manager, связывает подпакеты
├── errors.go           # доменные ошибки
├── auth/               # аутентификация, токены
├── chat/               # чат, сообщения
├── subscription/       # подписки, платежи
├── notification/       # push, email
└── match/              # рекомендации, матчинг
```

Каждый подпакет — свой Manager, свои модели. Главный `app.go` связывает их вместе.

## API слои

- Каждый API-слой имеет **свои модели** (не использует db-модели в JSON)
- Конвертеры `NewEntity(db *db.Entity) *Entity` в каждом слое
- `//go:generate go tool zenrpc` в server.go

### VT CRUD-сервис — 7 методов
Count, Get, GetByID, Add, Update, Delete, Validate + хелперы byID, dbSort, isValid.

### Три типа моделей VT
Entity (полная), EntitySearch (фильтры), EntitySummary (для списков).

## Стек

| Компонент | Библиотека |
|-----------|-----------|
| HTTP | labstack/echo |
| RPC | vmkteam/zenrpc/v2 |
| Middleware | vmkteam/zenrpc-middleware |
| ORM | go-pg/pg/v10 |
| Logging | vmkteam/embedlog (slog) |
| Metrics | prometheus/client_golang |
| Errors | getsentry/sentry-go |
| Validation | go-playground/validator/v10 |
| Config | TOML |
| Code gen | zenrpc, mfd-generator, rpcgen, colgen |
| Cron | vmkteam/cron |
| Appkit | vmkteam/appkit |

## Паттерны масштабирования

Абстрактные примеры из реальных production-проектов.

### Несколько RPC-серверов

Большой проект может иметь несколько zenrpc-серверов на разных endpoint'ах:

```go
type App struct {
    srv         *zenrpc.Server  // основной API /v1/rpc/
    srvDebug    *zenrpc.Server  // debug API /v1/debug/
    srvInternal *zenrpc.Server  // internal API (server-to-server)
}
```

Каждый сервер — свои middleware, namespace'ы, авторизация.

### Интеграционные пакеты

Внешние сервисы и клиенты в `pkg/client/`:

```
pkg/client/
├── othersrv/      # rpcgen-клиент другого сервиса
├── push/          # Firebase push
├── sms/           # SMS-провайдер
└── geoip/         # GeoIP (MaxMind)
```

В `pkg/` — только значимые пакеты проекта (app, db, rpc, vt, domain).

### Rpcgen endpoints (клиентогенерация на лету)

Для публичных API — генерация клиентов прямо с endpoint'а:

```go
a.echo.Any("/v1/rpc/api.ts", appkit.EchoHandlerFunc(rpcgen.Handler(gen.TSClient(typeMapper))))
a.echo.Any("/v1/rpc/api.go", appkit.EchoHandlerFunc(rpcgen.Handler(gen.GoClient(settings))))
a.echo.Any("/v1/rpc/api.swift", appkit.EchoHandlerFunc(rpcgen.Handler(gen.SwiftClient(settings))))
a.echo.Any("/v1/rpc/openrpc.json", appkit.EchoHandlerFunc(rpcgen.Handler(gen.OpenRPC("name", rpcUrl))))
```

### Config

```go
type Config struct {
    Server   ServerConfig
    Database db.Config
    Sentry   SentryConfig
    VFS      vfs.Config
}

type ServerConfig struct {
    Host    string
    Port    int
    IsDevel bool
    BaseURL string
}
```

Формат: TOML. Загрузка через `flag -config cfg/local.toml`.

## Чеклист нового сервиса

1. Создать `.pgd` схему
2. Сгенерировать SQL и `pkg/db/`
3. Определить нужен ли domain-слой
4. Спроектировать RPC/VT-сервисы
5. server.go с middleware и регистрацией
6. `make generate`
7. Конфиг (TOML), main.go, app.go

## Антипаттерны

- **Не** использовать db-модели в JSON-ответах API
- **Не** создавать интерфейсы без необходимости
- **Не** называть пакеты `util`, `service`, `handlers`, `domain`
- **Не** пропускать конвертеры между слоями
- **Не** делать domain-слой для простого CRUD
- **Не** использовать global state — DI через конструкторы
