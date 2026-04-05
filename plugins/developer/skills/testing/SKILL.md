---
name: testing
description: "Testing — паттерны тестирования vmkteam Go-сервисов: BDD с goconvey, реальная БД, без моков."
---

# Testing — паттерны тестирования

Паттерны тестирования для vmkteam Go-сервисов.

## Принципы

- **Существующие проекты** — используй текущий стиль (если goconvey — пиши goconvey)
- **Новые проекты и тесты** — `testify/assert` + `testify/require` в BDD стиле
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

## BDD стиль (goconvey)

```go
import . "github.com/smartystreets/goconvey/convey"

func TestDBUserService(t *testing.T) {
    Convey("Test UserService", t, func() {
        ctx := t.Context()
        srv := NewUserService(testDB)

        Convey("Positive testing", func() {
            Convey("Test CRUD", func() {
                inUser := User{
                    Login:    fmt.Sprintf("ivan_%d", time.Now().Unix()),
                    Password: "pwd",
                    StatusID: db.StatusEnabled,
                }

                // Add
                outUser, err := srv.Add(ctx, inUser)
                So(err, ShouldBeNil)
                So(outUser, ShouldNotBeNil)
                So(outUser.ID, ShouldBeGreaterThan, 0)

                // GetByID
                u, err := srv.GetByID(ctx, outUser.ID)
                So(err, ShouldBeNil)
                So(u.Login, ShouldEqual, inUser.Login)

                // Update
                u.Login = "updated"
                ok, err := srv.Update(ctx, *u)
                So(err, ShouldBeNil)
                So(ok, ShouldBeTrue)

                // Delete
                ok, err = srv.Delete(ctx, outUser.ID)
                So(err, ShouldBeNil)
                So(ok, ShouldBeTrue)
            })
        })

        Convey("Negative testing", func() {
            Convey("Empty login", func() {
                _, err := srv.Add(ctx, User{Login: "", Password: "pwd", StatusID: db.StatusEnabled})
                So(err, ShouldNotBeNil)
            })
        })
    })
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
// Использование
entity, clean := test.Entity(t, dbo, nil)
defer clean()
```

## Тестовая БД с seed data

Для сложных проектов — дамп тестовой БД с seed data:

```makefile
# Пересоздать из дампа
db-test:
	@dropdb --if-exists $(TEST_PGDATABASE)
	@createdb -E UTF-8 -O postgres -T template0 $(TEST_PGDATABASE)
	@pg_restore -O -x --disable-triggers -d $(TEST_PGDATABASE) docs/schema.dump
	@pg_restore -O -x --disable-triggers -d $(TEST_PGDATABASE) docs/seed.dump

# Сохранить текущее состояние
db-test-dump:
	@pg_dump -Fc -O -x -s $(TEST_PGDATABASE) > docs/schema.dump
	@pg_dump -Fc -O -x -a -t 'public.*' $(TEST_PGDATABASE) > docs/seed.dump
```

## mfd-generator dbtest (если используется)

```bash
make mfd-db-test
```

Генерирует фабрики в `pkg/db/test/` с gofakeit/v7:
- Паттерн: `func Entity(t, dbo, in, ...OpFunc) (*db.Entity, Cleaner)`
- Cleaner: `defer clean()` для автоочистки
- `WithFakeEntity()` — случайные данные
- `NextID()` — атомарный инкремент для параллельных тестов

## Правила

1. **TestDB префикс** для всех тестов с базой — `test-short` их пропускает
2. **Нет моков** — реальная БД, реальные сервисы
3. **BDD стиль** — Convey/So (goconvey) или assert (testify)
4. **Каждый тест создаёт свои данные** и чистит за собой
5. **Используй стиль проекта** — не навязывай другой фреймворк
