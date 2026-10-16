---
name: mfd
description: "MFD Generator — генерация Go-кода из PostgreSQL-схемы (модели, репозитории, фабрики тестов). Используй при правке .mfd или docs/model/*.xml, запуске `make generate`/`make mfd-*`, новой таблице или колонке, добавлении search-полей, фильтра или выборки по колонке, разбиении на неймспейсы, db-test фабриках."
---

# MFD Generator

Upstream: https://github.com/vmkteam/mfd-generator

Генерирует Go-код (модели, репозитории, VT-сервисы) из XML-описания схемы PostgreSQL. Запускай через `--help` бинарника для полного списка флагов.

## Makefile-цели (vmkteam-конвенция)

- **XML из БД:** `make mfd-xml`, `make mfd-vt-xml`, `make mfd-xml-lang`
- **Go-код:** `make mfd-model`, `make mfd-repo NS=<ns>`, `make mfd-db-test`
- **VT/UI:** `make mfd-vt-rpc NS=<ns>`, `make mfd-vt-template NS=<ns>`
- **Финал:** `make generate` (zenrpc + colgen)

### Новая таблица
```bash
make mfd-xml && make mfd-model && make mfd-repo NS=<ns> && make mfd-db-test
make mfd-vt-xml && make mfd-vt-rpc NS=<ns> && make generate
```

`mfd-xml` на новой таблице спрашивает неймспейс интерактивно. Неинтерактивно — флаг `-n` (формат `ns:t1,t2;ns2:t3`; README генератора ошибочно пишет `=`, с ним флаг молча игнорируется — [#73](https://github.com/vmkteam/mfd-generator/issues/73)):
```bash
mfd-generator xml -c "$CONN" -m docs/model/<project>.mfd -t "t1,t2" -n "session:t1;journal:t2"
```

### Изменение существующей
```bash
make mfd-xml && make mfd-model && make mfd-repo NS=<ns> && make mfd-db-test
```

Сначала примени миграцию к локальной БД (/pgmigrator): `mfd-xml` читает схему из базы.

## Layout

- `docs/model/<project>.mfd` — корневой MFD (PackageNames, TableMapping, GoPGVer)
- `docs/model/<namespace>.xml` — per-namespace Entities/Attributes/Searches

## Неймспейсы — по поддоменам

Таблицы делятся на неймспейсы так же, как домен на поддомены: вход и пользователи, основная работа, журнал, файлы — по 2–8 таблиц (gatesrv: `common`, `user`, `project`, `alert`). Один неймспейс на 20 таблиц даёт `XRepo` на сотни методов, и любой менеджер видит всё. Менеджер держит репозитории нужных неймспейсов; ручные методы — в `<ns>_ext.go`, общее — в `common_ext.go`.

Команда — с разбиением: `-n "auth:users,tokens;work:tasks,sprints"`, а не `-n "<project>:<все таблицы>"`. Уже свалено в один — разложи `<ns>.xml` по сущностям, поправь `TableMapping` в `.mfd` и перегенерируй `make mfd-repo NS=…` по каждому неймспейсу.

## Entity/Attribute — vmkteam-конвенции

- `Name` = Go-поле; PK автоматически переименовывается в `ID`
- `FK="User"` — имя **Entity**, не таблицы
- `Addable`/`Updatable` — флаги для INSERT/UPDATE
- Аудит-поля `createdAt`/`modifiedAt` → `Addable="false" Updatable="false"`
- `<Attribute>` — только из БД через `mfd-xml`, руками не вписывать: новую колонку генератор ставит в конец сущности (порядок колонок в БД после `ALTER … ADD COLUMN`). Руками в `<ns>.xml` правят `<Search>` и `GoType` jsonb — `mfd-xml` их сохраняет
- На каждый Attribute автоматически генерируется equals-search; удалённые вручную Searches **не восстанавливаются** при `mfd-xml`
- Переименование Name ломает ссылки из Searches/VT — искать и обновлять вручную

### Маппинг типов (нестандартное)

- `json`/`jsonb` → именованный тип `<EntityFieldName>` (не `map[string]any`)
- `bigint` → `int64`; `integer`/`serial` → `int`
- `numeric`/`double` → `float64`

### SearchType — полный список

`EQUALS`, `NOT_EQUALS`, `NULL`, `NOT_NULL`, `GE`/`LE`/`G`/`L`, `ILIKE`, `ARRAY` (IN), `NOT_INARRAY`, `ARRAY_CONTAINS` (ANY), `JSONB_PATH` (@>).

Все с префиксом `SEARCHTYPE_`.

### JSONB-поиск

`AttrName` использует `->` + обязательный `GoType`:
```xml
<Search Name="SmsCount" AttrName="Params->smsCount" SearchType="SEARCHTYPE_EQUALS" GoType="int" />
```

## Search прежде With

**Условие по колонке — поле Search, а не `search.With(...)`.** Нужен фильтр — добавь `<Search>` в `<ns>.xml` и `make mfd-model`: строка SQL кажется дешевле, но обходит типы и имена генератора.

| SQL | SearchType | Пример имени |
|---|---|---|
| `col IN (…)` / `NOT IN (…)` | `ARRAY` / `NOT_INARRAY` | `TaskIDs`, `StatusIDs`, `NotStatusIDs` |
| `col <> ?` | `NOT_EQUALS` | `NotKind` |
| `col IS NULL` / `IS NOT NULL` | `NULL` / `NOT_NULL` | `ArchivedAtNull`, `VerdictNotNull` |
| `col >= ?`, `<= ?`, `> ?`, `< ?` | `GE`, `LE`, `G`, `L` | `CreatedAtFrom`, `CreatedAtTo`, `DoneAtAfter`, `DoneAtBefore` |
| `jsonb->>'key' = ?` | `EQUALS` с `AttrName="Col->key"` и `GoType` | `ActorKind` |

Имена — как у генератора: `From` (`>=`), `To` (`<=`), `After` (`>`), `Before` (`<`), `Null`/`NotNull`, множественное число — `ARRAY`, префикс `Not` — исключение.

Что генератор не выражает — `EXISTS` и подзапросы, `OR` между колонками, `coalesce`, приведение типов (`(params->>'expiresAt')::timestamptz`), — **метод Search в `<ns>_ext.go`**, без литералов домена: значения — параметрами, вызов цепочкой:

```go
// pkg/db/session_ext.go
func (s *SessionSearch) WithRole(role string) *SessionSearch {
    s.With(`"t"."slotId" IN (SELECT "slotId" FROM slots WHERE role = ?)`, role)
    return s
}

// домен
search := (&db.SessionSearch{ProjectID: &id, EndedAtNull: new(true)}).WithRole(role)
```

`new(true)` — Go 1.26+; в старых версиях — переменная и `&v`.

`search.With(...)` в домене — только правила с литералами статусов и видов, которые не выразить полями (подзапрос `NOT EXISTS … "statusId" = ?` по константе домена). На ревью `With` с условием, которое покрывает поле Search или метод `_ext`, — minor.

Ловушки:
- поле `NULL`/`NOT_NULL` — `*bool`, значение не читается: ставь `true`, `false` условие **не** инвертирует;
- `ARRAY` с пустым срезом фильтр не ставит (см. «Известные баги»), а `IN (?)` с `pg.In` пустого списка в `With` даёт синтаксическую ошибку `IN ()`: пустой вход — ранний возврат;
- путь jsonb даёт `col->'a'->>'b'`: `NOT_NULL` по пути считает JSON `null` за NULL.

## Известные баги (mfd-generator ≤ v0.6.2)

Убрать раздел, когда исправят upstream: [#71](https://github.com/vmkteam/mfd-generator/issues/71), [#72](https://github.com/vmkteam/mfd-generator/issues/72).

- **`Add<Entity>` не возвращает значения базы.** Колонки с `Addable="false"` (`createdAt`) исключаются из INSERT только при пустых `ops` и назад не читаются: без ops в возвращённой модели нулевое время (`0001-01-01` уходит в ответ API), с любым op колонка попадает в INSERT и из-за `use_zero` в базу пишется `0001-01-01`. Тот же шаблон у `Update<Entity>` для `Updatable="false"`. Обход — примитив в `common_ext.go` на каждый `Add`, чей объект отдаётся наружу или который вызывается с ops:
  ```go
  // WithDefaults: колонки cols заполнит DEFAULT базы, модель получит вставленную строку.
  func WithDefaults(cols ...string) OpFunc {
      return func(query *orm.Query) {
          WithoutColumns(cols...)(query)
          query.Returning("*")
      }
  }
  ```
  Тест create проверяет и поля, заполненные базой (/testing).
- **`ARRAY`-фильтр по `len(…) > 0`, а не `!= nil`.** Пустой срез — «без фильтра»: забытая проверка пустого входа отдаёт всю таблицу, а под `UpdateBy` — обновляет всю таблицу. Пустой вход проверяй до запроса.

## Маркер generated-файлов

```go
// Code generated by mfd-generator v0.6.2; DO NOT EDIT.
```

Не редактировать. Исключение — `model_params.go` (append-only).
