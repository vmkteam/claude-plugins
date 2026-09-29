---
name: testing
description: "Testing — используй всегда, когда пишешь или правишь Go-тесты (*_test.go), в том числе по сценариям Given/When/Then из spec: фреймворк как в соседних файлах, префикс TestDB, фабрики pkg/db/test, реальная БД без моков. Также при настройке TestMain/test-short и когда тесты падают в gate, но проходят локально."
---

# Testing — паттерны тестирования

Паттерны тестирования для vmkteam Go-сервисов.

## Принципы

- **Фреймворк — как в соседних `*_test.go`** пакета: стили в одном пакете не смешивай. В новых пакетах и проектах — `t.Run` + `testify/assert` + `testify/require`, table-driven для множественных кейсов. Существующие goconvey-тесты не переписывай ради переписывания
- **Без моков** — тестируем реальный транспорт, реальную базу
- **TestDB префикс** — тесты с БД именуются `TestDB*`
- **test-short** пропускает DB-тесты через regex `Test[^D][^B]`
- **Покрытие** — happy path и ошибочные пути: пустой ввод, слишком длинный, граничные значения, отсутствующая запись, повторный вызов. Непокрытый ошибочный путь — дыра
- **Инварианты** — если в задаче есть числовой или глобальный инвариант («≤ N», «суммарно», «во всех ветках»), первым пиши тест на худший случай (максимум полей, длины, количества) и убедись, что он падает на старом коде

## Makefile targets

```makefile
# Все тесты (включая DB)
test:
	@PGDATABASE=$(TEST_PGDATABASE) go test -count=1 $(GOFLAGS) -coverprofile=coverage.txt -covermode count $(PKG)

# Быстрые тесты (без DB) — пропускает TestDB*
test-short:
	@go test $(GOFLAGS) -v -test.short -test.run="Test[^D][^B]" -coverprofile=coverage.txt -covermode count $(PKG)

# Пересоздать тестовую БД
db-test:
	@dropdb --if-exists $(TEST_PGDATABASE)
	@createdb -E UTF-8 $(TEST_PGDATABASE)
	@psql -f docs/schema.sql $(TEST_PGDATABASE)
```

## Канонический стиль (t.Run + testify)

```go
import (
    "testing"

    "github.com/stretchr/testify/assert"
    "github.com/stretchr/testify/require"
)

func TestDBUserService(t *testing.T) {
    ctx := t.Context()
    srv := NewUserService(testDB)

    t.Run("CRUD", func(t *testing.T) {
        in := User{
            Login:    fmt.Sprintf("ivan_%d", time.Now().Unix()),
            Password: "pwd",
            StatusID: db.StatusEnabled,
        }

        out, err := srv.Add(ctx, in)
        require.NoError(t, err)
        require.NotNil(t, out)
        assert.Greater(t, out.ID, 0)

        got, err := srv.GetByID(ctx, out.ID)
        require.NoError(t, err)
        assert.Equal(t, in.Login, got.Login)

        got.Login = "updated"
        ok, err := srv.Update(ctx, *got)
        require.NoError(t, err)
        assert.True(t, ok)

        ok, err = srv.Delete(ctx, out.ID)
        require.NoError(t, err)
        assert.True(t, ok)
    })

    t.Run("empty login is rejected", func(t *testing.T) {
        _, err := srv.Add(ctx, User{Login: "", Password: "pwd", StatusID: db.StatusEnabled})
        require.Error(t, err)
    })
}
```

`require.*` обрывает тест при ошибке (когда дальше бессмысленно). `assert.*` — мягкая проверка, продолжает выполнение.

## Table-driven

```go
func TestValidateLogin(t *testing.T) {
    cases := []struct {
        name    string
        login   string
        wantErr bool
    }{
        {"valid", "ivan", false},
        {"empty", "", true},
        {"too short", "ab", true},
        {"too long", strings.Repeat("a", 65), true},
    }
    for _, tc := range cases {
        t.Run(tc.name, func(t *testing.T) {
            err := ValidateLogin(tc.login)
            if tc.wantErr {
                require.Error(t, err)
            } else {
                require.NoError(t, err)
            }
        })
    }
}
```

## Сценарии Given/When/Then → тесты

Spec в /solve и подзадачи /decompose описывают поведение сценариями Given/When/Then. Это формат постановки, а не фреймворк: тест пишется в стиле пакета, по одному на сценарий.

| Сценарий | Тест |
|---|---|
| `Scenario` | подтест `t.Run` с текстом сценария в имени — упавший тест сразу указывает на сценарий из spec |
| `Given` | подготовка данных фабриками из `pkg/db/test` с конкретными значениями из сценария |
| `When` | один вызов тестируемого метода |
| `Then` | проверки `require` / `assert` |
| `Scenario Outline` + `Examples` | table-driven: строка `Examples` — кейс |

Сценарии из spec:

```gherkin
Scenario: владелец отменяет новый заказ
  Given заказ пользователя в статусе New
  When пользователь вызывает order.Cancel
  Then статус заказа — Cancelled

Scenario Outline: заказ в финальном статусе отменить нельзя
  Given заказ пользователя в статусе <status>
  When пользователь вызывает order.Cancel
  Then ошибка ErrInvalidStatus
  Examples:
    | status    |
    | Delivered |
    | Cancelled |
```

Тест:

```go
func TestDBOrderCancel(t *testing.T) {
    ctx := t.Context()
    srv := NewOrderService(testDB)
    repo := db.NewOrderRepo(testDB)

    t.Run("владелец отменяет новый заказ", func(t *testing.T) {
        order, clean := test.Order(t, testDB, &db.Order{StatusID: db.StatusNew})
        defer clean()

        _, err := srv.Cancel(withUser(ctx, order.UserID), order.ID) // withUser — хелпер проекта
        require.NoError(t, err)

        got, err := repo.OrderByID(ctx, order.ID)
        require.NoError(t, err)
        assert.Equal(t, db.StatusCancelled, got.StatusID)
    })

    t.Run("заказ в финальном статусе отменить нельзя", func(t *testing.T) {
        cases := []struct {
            name   string
            status int
        }{
            {"Delivered", db.StatusDelivered},
            {"Cancelled", db.StatusCancelled},
        }
        for _, tc := range cases {
            t.Run(tc.name, func(t *testing.T) {
                order, clean := test.Order(t, testDB, &db.Order{StatusID: tc.status})
                defer clean()

                _, err := srv.Cancel(withUser(ctx, order.UserID), order.ID)
                require.ErrorIs(t, err, ErrInvalidStatus)
            })
        }
    })
}
```

В legacy-пакетах на goconvey тот же сценарий ложится на вложенные `Convey("Given ...")` → `Convey("When ...")` → `So(...)`.

## Setup — TestMain и тестовая БД

```go
// server_test.go
var testDB db.DB

func TestMain(m *testing.M) {
    testDB = NewTestDB()
    os.Exit(m.Run())
}

func NewTestDB() db.DB {
    cfg, err := pg.ParseURL(os.Getenv("DB_CONN"))
    if err != nil {
        cfg, _ = pg.ParseURL("postgresql://localhost:5432/test-mysrv?sslmode=disable")
    }
    dbc := pg.Connect(cfg)
    return db.New(dbc)
}
```

## Тестовые хелперы (pkg/db/test)

Генерируются через `make mfd-db-test` (/mfd). Содержат фабрики, Cleaner, NextID — не пиши хелперы вручную.

```go
entity, clean := test.Entity(t, dbo, nil)
defer clean()
```

## Тестовая БД с seed data

Для сложных проектов — дамп тестовой БД с seed data:

```makefile
db-test:
	@dropdb --if-exists $(TEST_PGDATABASE)
	@createdb -E UTF-8 -O postgres -T template0 $(TEST_PGDATABASE)
	@pg_restore -O -x --disable-triggers -d $(TEST_PGDATABASE) docs/schema.dump
	@pg_restore -O -x --disable-triggers -d $(TEST_PGDATABASE) docs/seed.dump

db-test-dump:
	@pg_dump -Fc -O -x -s $(TEST_PGDATABASE) > docs/schema.dump
	@pg_dump -Fc -O -x -a -t 'public.*' $(TEST_PGDATABASE) > docs/seed.dump
```

## mfd-generator dbtest

```bash
make mfd-db-test
```

Генерирует фабрики в `pkg/db/test/` с gofakeit/v7:
- `func Entity(t, dbo, in, ...OpFunc) (*db.Entity, Cleaner)` — фабрика с автоочисткой
- `WithFakeEntity()` — случайные данные
- `NextID()` — атомарный инкремент для параллельных тестов

## Герметичность

Тест не должен полагаться на строки, которые уже лежат в БД: сиды из init.sql, «дефолтные» записи, данные других тестов. База пересоздаётся между прогонами, и сид может не доехать. Нужна запись — создай её в самом тесте (фабрикой или идемпотентным insert) и проверяй только свои данные.

Тесты красные в gate, а локально зелёные — сначала воспроизведи окружение gate: `make db-test && make test`. Пересоздание БД обязательно: на тёплой базе битые сиды и схема не видны. Только после этого делай вывод о внешней причине.

## Правила

1. `TestDB` префикс для всех тестов с базой — `test-short` их пропускает
2. Нет моков — реальная БД, реальные сервисы
3. Фреймворк — как в соседних файлах пакета; в новых пакетах — `t.Run` подтесты + testify (`require` для fatal, `assert` для soft)
4. Table-driven когда множественные кейсы на одном поведении
5. Каждый тест создаёт свои данные и чистит за собой
