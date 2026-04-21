---
name: testing
description: "Testing — паттерны тестирования Go-сервисов: t.Run + testify, table-driven, реальная БД, без моков. Используй при написании новых тестов, правке существующих или настройке TestMain/test-short."
---

# Testing — паттерны тестирования

Паттерны тестирования для vmkteam Go-сервисов.

## Принципы

- **Канонический стиль** — `t.Run` + `testify/assert` + `testify/require`. Table-driven для множественных кейсов
- **Legacy на goconvey** — не переписывай ради переписывания, но новые тесты в таких проектах тоже на `t.Run` + testify
- **Без моков** — тестируем реальный транспорт, реальную базу
- **TestDB префикс** — тесты с БД именуются `TestDB*`
- **test-short** пропускает DB-тесты через regex `Test[^D][^B]`

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

## Правила

1. `TestDB` префикс для всех тестов с базой — `test-short` их пропускает
2. Нет моков — реальная БД, реальные сервисы
3. `t.Run` подтесты + testify (`require` для fatal, `assert` для soft) — канонический стиль для нового кода
4. Table-driven когда множественные кейсы на одном поведении
5. Каждый тест создаёт свои данные и чистит за собой
