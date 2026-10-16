---
name: gold-arch
description: "Gold Architecture — слои db → domain → API, модели домена, транзакции, раскладка пакетов Go-сервисов vmkteam. Используй при любой задаче, которая добавляет или меняет пакет, менеджер, воркер, RPC/MCP-сервис, бота, интеграцию или модель; при переносе кода из соседнего сервиса; перед ревью структуры."
---

# Gold Architecture — Go API-сервисы vmkteam

Шаблон: [gold-apisrv](https://github.com/vmkteam/gold-apisrv). Философия: [vmkteam.dev](https://vmkteam.dev).

JSON-RPC 2.0 поверх echo. Простота важнее абстракций. **Без интерфейсов** кроме как в domain (если нужно).

> **Слоистость — осознанный выбор vmkteam, а не универсальная Go-идиома.** Flat packages идиоматичнее в малых и средних Go-проектах. Мы используем слоистую (db → domain → rpc) потому что: (1) типичный сервис — CRUD + фоновые процессоры + несколько API-endpoint'ов (public/vt/debug), (2) явные конвертеры между слоями убирают риск db-моделей в JSON, (3) кодогенерация (mfd/colgen/zenrpc) лучше ложится на чёткие границы слоёв. Вне vmkteam-контекста эта структура может быть избыточна — не применяй её слепо.

## Спека против скилла

Если спека проекта или образец (соседний сервис) расходится с этим скиллом — не выбирай молча: назови расхождение и спроси, что верно; до ответа следуй скиллу. Образцы старше скилла и могут нести устаревшие решения: vmksrv держит клиент Bot API в `pkg/tg` рядом с карточками, ringsrv — MCP-сервер в `pkg/rpc`.

## Слои и зависимости

```
pkg/rpc, pkg/vt, pkg/debug, pkg/mcp, pkg/tg   ← API: свои модели, конвертеры, zenrpc / mcpkit / бот
         ↓
pkg/<projectname>                              ← Domain: Manager, модели домена, правила
         ↓
pkg/db                                         ← ORM-модели, EntityRepo, OpFunc
         ↓
PostgreSQL
```

Зависимости строго вниз. API никогда не отдаёт db-модели в JSON — только свои модели через конвертеры (см. `/colgen`). Есть domain-слой — API работает с моделями домена и `pkg/db` не импортирует (см. «Модели домена»). Нет domain-слоя (простой VT CRUD) — API конвертирует db-модели сам.

## Именование пакетов (vmkteam-конвенция)

| Так | Не так |
|---|---|
| `db` | `repository` |
| `rpc` | `handlers`, `api` |
| `<projectname>` | `domain`, `logic`, `service` |
| `vt` / `debug` | `admin`, `backoffice` |
| `mcp` | `mcprpc`, `mcpserver` |

## Структура

```
cmd/<srvname>/main.go
pkg/app/                  App struct, DI, lifecycle, routing, config, metrics
pkg/app/cron.go           newCron(), CronConfig — расписание из TOML (/cron)
pkg/db/                   generated ORM; ручное — <ns>_ext.go, общее — common_ext.go
pkg/<projectname>/        domain
    <projectname>.go      константы, ошибки, doc пакета
    model.go              модели домена (embed db) и формы входа/выхода менеджеров
    collection.go         colgen
    query.go              выборки домена поверх mfd-Search
    <поддомен>/           подпакет поддомена: auth/, card/...
pkg/rpc/                  public API, файлы по доменам (auth.go, chat.go — не один большой)
pkg/vt/ | pkg/debug/      admin API, CRUD + Validator
pkg/mcp/                  MCP-сервер (vmkteam/mcpkit); в app — с алиасом: имя mcp занято mcpkit/mcp
pkg/tg/                   бизнес-логика бота: карточки, команды, решения
pkg/client/<name>/        клиенты внешних API: rpcgen-клиенты чужих сервисов, Telegram Bot API, GitLab, push, sms
cfg/local.toml.dist
docs/*.pgd | *.pdd        схема БД
```

В `pkg/` — только значимые пакеты. Клиент внешнего API — всегда в `pkg/client/<name>/`, даже если образец держит его рядом с бизнес-логикой: в `pkg/tg` — только то, что бот решает и показывает. Периодические задачи — методы менеджеров, расписание — `pkg/app/cron.go` (/cron), а не пакет `<projectname>/cron`.

Пакет домена больше ~3 тыс. строк — ищи поддомены: вход и пользователи, уведомления и карточки, биллинг. Подпакет выделяй, когда у поддомена свой менеджер и он не меняет состояния сущностей ядра. Подпакет зависит от ядра, ядро от него — нет.

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

Неймспейсы mfd — по поддоменам, 2–8 таблиц, а не один на сервис: менеджер держит репозитории нужных неймспейсов (/mfd).

### db — тонкий и универсальный

Ручные файлы db-слоя (`<ns>_ext.go`, `common_ext.go`) содержат только примитивы без знания домена:

| Примитив | Для чего |
|---|---|
| `WithWhere(cond, params…)` | условие CAS: с `WithColumns` и сгенерированным `Update<Entity>` строка пишется, только если условие ещё выполнено |
| `UpdateBy(ctx, model, search, set, params…)` | массовое обновление по Search с `RETURNING *` |
| `WithLock(lock)` | `FOR UPDATE [SKIP LOCKED]` в транзакции — блокировка для claim |
| `WithOrder(expr, params…)` | сортировка выражением |
| методы Search (`WithRole(role)`) | условия, которые генератор не выражает: `OR` между колонками, подзапросы (/mfd) |

Плюс рекурсивные и оконные запросы. Образец примитивов — hubsrv `pkg/db/common_ext.go`; нет в проекте — добавь туда же.

**В db нет литералов состояний, видов и ролей** и нет имён бизнес-выборок («claimable», «активные сессии»): значения приходят параметрами, а правила — функции домена в `query.go` над mfd-Search. Условие по колонке — поле Search (/mfd, «Search прежде With»); `search.With(...)` в домене — только правила с литералами, которые генератор не выражает. Атомарный claim: условие — в `query.go` домена, блокировка — `WithLock` из db.

Уникальность и существование — инвариант схемы (частичный UNIQUE, CHECK, FK). Пример: «code уникален среди активных» — частичный UNIQUE-индекс `WHERE "statusId" <> 3`, а не `COUNT` в ручном методе. Комментарий-обоснование не делает ручной метод правомерным; на ревью ручной метод db с бизнес-условием — major с указанием, в какой слой перенести.

## Domain слой

**Нужен когда:** бизнес-логика сложнее CRUD, фоновый процессор, несколько API-слоёв делят логику.
**НЕ нужен когда:** простой CRUD — VT работает напрямую с db.

Паттерны:
- `Manager` — синхронные операции (`Create`, `Cancel`...)
- `Processor` — долгоживущие горутины (очереди, подписки): `Run(ctx)` блокирующий + `ProcessX(ctx, ...)`. Периодическая задача — не Processor, а метод менеджера `func(ctx) error` в расписании (/cron).

Большой домен — подпакеты по поддоменам (см. «Структура»), главный `app.go` связывает.

### Модели домена

Модели домена встраивают модели db:

```go
type Task struct{ db.Task }

func NewTask(in *db.Task) *Task {
    if in == nil {
        return nil
    }
    return &Task{Task: *in}
}

func (t *Task) ToDB() *db.Task { return &t.Task }
```

Списки — colgen `MapP(db)` (/colgen). Экспортируемые методы менеджеров принимают и возвращают модели домена и формы (`TaskCreate`), db-типы — только внутри пакета домена. API-слои (`rpc`, `mcp`, бот) **не импортируют `pkg/db`**, исключение — `db.DB` для SQL-логгера в `server.go`. Проверка — depguard в `linters.settings.depguard.rules` `.golangci.yml`:

```yaml
api:
  files: ["**/pkg/rpc/*.go", "**/pkg/mcp/*.go", "**/pkg/tg/*.go", "!**/server.go", "!$test"]
  deny: [{pkg: "<module>/pkg/db", desc: "API работает с моделями домена"}]
```

### Бизнес-объекты

Домен работает с бизнес-объектами, а не с db-моделями. Из репозитория — сразу `NewX`, обёрток над сгенерированными чтениями не заводим; запись — через `ToDB()`:

```go
dbTask, err := m.repo.TaskByID(ctx, id)
if err != nil {
    return nil, err
}
t := NewTask(dbTask)
if t == nil {
    return nil, ErrNotFound
}
if t.IsClosed() {
    return nil, ErrTaskClosed
}
// ...
_, err = m.repo.UpdateTask(ctx, t.ToDB(), db.WithColumns(db.Columns.Task.StatusID))
```

**Правила — методы объектов**, домен читается на своём языке: `if t.CanCancel(user)` вместо проверки статуса и владельца по месту. Имя предиката — по смыслу вопроса, а не всегда `Is`:

| Вопрос | Форма | Пример |
|---|---|---|
| состояние, вид | `Is…`, у коллекции `Are…` | `t.IsClosed()`, `l.IsFree(now)`, `a.IsVisibleTo(p)`, `tasks.AreClosed()` |
| есть ли что-то у объекта | `Has…` | `s.HasAgents(now)`, `t.HasCode(code)` |
| можно ли действие | `Can…` | `q.CanAnswer(p)`, `t.CanCancel(user)` |
| нужно ли действие | `Needs…` | `t.NeedsReview()` |
| правило поведения | глагол в 3-м лице | `t.AutoMerges(severity)`, `s.AwaitsDecision()` |

Производные значения — без `Get`: `t.Key()`, `s.Actor()`. Предикат не называй существительным (`Leftover(t)` → `IsLeftover(t)`) и не прячь отрицание в имя (`IsNotStarted()` → `!IsStarted()`). Сравнение статуса или вида вне `model.go` и свободная функция над db-моделью (`taskClosed(t.StatusID)`) — повод добавить метод. Коллекции colgen (`IDs`, `Index`, `Group…`) — на бизнес-объектах в `collection.go` домена; в `pkg/db` colgen не кладём.

### Транзакции

`db.TxManager` встраивается в менеджеры домена: `DB()`, `Tx()`, `SetTx(tx)`, `RequireTx()`, `Conn()` (транзакция, если она есть, иначе соединение). Переход в транзакцию — один хелпер менеджера (`inTx`, `runInLock`): `RunInTransaction` или `RunInLock`, копия менеджера с `repo.WithTransaction(tx)` и `SetTx(tx)`. `RunInTransaction` руками в каждом методе не открывать. Образец — vmkteam-reviewer: `pkg/db/db.go`, `pkg/reviewer/manager.go`.

## API слой

- Свои модели (не db-структуры в JSON)
- Конвертеры через `/colgen`
- `//go:generate go tool zenrpc` в server.go

Конвертеры называются по направлению:

| Направление | Имя |
|---|---|
| db → домен | `NewX(*db.X) *X` |
| домен → API | `newX(*<projectname>.X) *X`; по значению — для `mcp.Map` |
| API → домен | метод `.ToModel()` |
| домен → db | метод `.ToDB()` |
| списки | colgen `Map`/`MapP`; обратно — `Map(list, X.ToModel)` |

**VT CRUD — 7 методов:** Count, Get, GetByID, Add, Update, Delete, Validate + хелперы `byID`, `dbSort`, `isValid`.

**Три типа моделей VT:** `Entity` (полная), `EntitySearch` (фильтры), `EntitySummary` (для списков).

## Интеграции

Клиент внешнего API — `pkg/client/<name>/`; что делать с ответом, решает домен или бот.

Текст сообщения с разметкой (Telegram HTML, почта, Slack) собирай построителем, а не `[]string` + `strings.Join` с ручным `esc()` у каждого аргумента: `P(format, args…)` экранирует строковые аргументы сам, и текст пользователя или агента не станет разметкой; готовую разметку (ссылку, список) передавай отдельным типом (`markup`), который не экранируется. Режь текст до экранирования, длинный — по целым строкам, чтобы не порвать тег. Образец — hubsrv `pkg/tg/msg.go`.

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

HTTP: `labstack/echo`. RPC: `vmkteam/zenrpc/v2` + `zenrpc-middleware`. MCP: `vmkteam/mcpkit`. ORM: `go-pg/pg/v10`. Log: `vmkteam/embedlog` (slog). Metrics: `prometheus/client_golang`. Errors: `sentry-go`. Validate: `go-playground/validator/v10`. Cron: `vmkteam/cron`. Utils: `vmkteam/appkit`. Config: TOML. Codegen: zenrpc, mfd-generator, rpcgen, colgen.

## Чеклист нового сервиса

1. `.pgd` схема → 2. SQL, неймспейсы mfd по поддоменам, `pkg/db` → 3. решить про domain → 4. RPC/VT сервисы → 5. server.go (middleware, регистрация) → 6. `make generate` → 7. TOML config, main.go, app.go.

## Антипаттерны

- db-модели в JSON
- db-модели в сигнатурах экспортируемых методов домена; импорт `pkg/db` в API при наличии домена
- литералы состояний и имена бизнес-выборок в `pkg/db`
- свободные функции над db-моделями вместо методов бизнес-объекта
- `RunInTransaction` руками в каждом методе менеджера
- интерфейсы без необходимости
- пакеты `util`, `service`, `handlers`, `domain`
- пропуск конвертеров между слоями
- domain-слой ради простого CRUD
- global state вместо DI через конструкторы
- новые фильтры и выборки ручным SQL вместо mfd-Search или ограничения схемы
- один неймспейс mfd на весь сервис
- свой пакет `<projectname>/cron` или генерик `Job` поверх `vmkteam/cron`
