---
name: pgd
description: "PGD — справочник по формату и CLI pgDesigner. Используй при работе с .pgd файлами."
paths: "**/*.pgd"
---

# PGD — pgDesigner формат и CLI

`.pgd` — git-friendly XML-формат [pgDesigner](https://pgdesigner.io) для схем PostgreSQL.
Источник правды — спецификация https://pgdesigner.io/docs/pgd-format и XSD `pgd-format.xsd` (в репозитории
pgdesigner — `docs/pgd-format/`). Скилл сверен с pgdesigner **0.0.6** (`pgdesigner version`); на другой версии
ловушки ниже перепроверь.

CLI: `pgdesigner` (не `pgd`).

## Non-obvious правила редактирования

- **Без числовых ID** — объекты по имени; кросс-схемно через `schema.table`
- **`<index>` — на уровне `<schema>`, НЕ внутри `<table>`** (частая ошибка при конверсии из PDD)
- **Порядок элементов в `<table>`:** column → pk → fk → unique → check → exclude → with → partition-by → partition
- **Порядок элементов в `<index>`:** ключи → `<include>` → `<with>` → `<where>`. Ключи — `<column>` и `<expression>` вперемешку, в порядке ключа индекса. Старый порядок (`<where>` перед `<include>`) pgdesigner читает, но XSD 0.0.6 его отвергает
- **Булевы — строки** `"true"`/`"false"` (не `"0"`/`"1"` как в PDD)
- **Сырой SQL — текстом элемента в CDATA:** `<check>`, `<expression>` и `<where>` индекса, `<bound>` партиции, `<query>` представления, `<body>` функции, `<using>`/`<with-check>` политики, `<constraint>` домена
- **Атрибутом, не текстом:** `default="…"` колонки и `<generated expression="…">` — XSD требует атрибут. Текст или CDATA внутри `<generated>` `generate` превращает в `GENERATED ALWAYS AS ()`; `lint` ловит это как E033
- **`nullable` default `"true"`** — для NOT NULL ставь явно `nullable="false"`
- **`comment="…"`** у `<table>` и `<column>` — это `COMMENT ON`
- **Действия FK указывай явно:** `restrict`, `cascade`, `set-null`, `set-default`, `no action` (с пробелом, остальные через дефис). Без атрибута `generate` пишет `NO ACTION`, хотя XSD объявляет `restrict`, и `lint` молчит; W015 срабатывает только на явный `no action`, а `lint -fix` меняет его на `restrict`
- **Тип из не-public схемы — со схемой:** `type="app.level"`, иначе PostgreSQL ищет его по `search_path` (W024)
- Атрибуты на одной строке — иначе git-diff будет шумный

## Корень

```xml
<?xml version="1.0" encoding="UTF-8"?>
<pgd version="1" pg-version="18" default-schema="public">
```

## Иерархия

Все разделы необязательны; порядок — канонический:

```
<pgd>
├── <project>/<settings>     <naming>, <defaults>, <lint ignore-rules>
├── <database>               имя, кодировка, коллация
├── <roles> <tablespaces> <extensions>
├── <types>                  enum, composite, domain, range
├── <sequences>
├── <schema>
│   ├── <table>
│   │   └── column, pk, fk, unique, check, exclude, with,
│   │       partition-by, partition
│   └── <index>              <-- на уровне schema!
├── <views> <functions> <triggers> <rules> <policies>
├── <comments> <grants>
└── <layouts>                позиции, группы и цвета редактора
```

## Канонические сниппеты

Enum — порядок `<label>` = порядок значений в PostgreSQL (см. ловушки `diff`):
```xml
<enum name="user_status" schema="public">
  <label>active</label>
  <label>inactive</label>
</enum>
```

FK (inline в `<table>`, в отличие от PDD):
```xml
<fk name="fk_orders_user" to-table="users" on-delete="cascade" on-update="restrict">
  <column name="user_id" references="id"></column>
</fk>
```

Индекс по выражению / covering / partial / opclass:
```xml
<index name="idx_users_lower_email" table="users" using="btree">
  <expression><![CDATA[lower(email)]]></expression>
  <include><column name="name"></column></include>
  <where><![CDATA[deleted_at IS NULL]]></where>
</index>
<index name="idx_users_name_trgm" table="users" using="gin">
  <column name="name" opclass="gin_trgm_ops"></column>
</index>
<index name="idx_users_full_name_trgm" table="users" using="gin">
  <expression opclass="gin_trgm_ops"><![CDATA[lower(full_name)]]></expression>
</index>
```

`opclass`, `order` и `nulls` у `<expression>` — как у `<column>`. Одно `<expression>` — один ключ: несколько ключей через запятую в одном выражении — W023.

IDENTITY и generated (`stored="false"` — VIRTUAL, PG18):
```xml
<column name="id" type="bigint" nullable="false">
  <identity generated="always"></identity>
</column>
<column name="full_name" type="text">
  <generated expression="first_name || ' ' || last_name" stored="true"></generated>
</column>
```

Партицирование — границу по `timestamptz` пиши со смещением, иначе она зависит от таймзоны сессии, которая накатывала миграцию (и см. ловушку сверки с базой):
```xml
<partition-by type="range"><column name="created_at"></column></partition-by>
<partition name="events_2024">
  <bound>FOR VALUES FROM ('2024-01-01 00:00:00+00') TO ('2025-01-01 00:00:00+00')</bound>
</partition>
```

Полный синтаксис всех тегов и атрибутов: https://pgdesigner.io/docs/pgd-format.

## Ловушки 0.0.6

### `diff` → миграция

`diff` 0.0.6 выдаёт FK и комментарии новых таблиц, смену и снятие generated (`SET EXPRESSION`, `DROP EXPRESSION`),
пересоздание индекса при смене выражения, `INCLUDE`, `NULLS NOT DISTINCT` и `WITH`, `ADD VALUE … AFTER` для enum,
переименование индексов и ограничений. Миграцию всё равно проверяй: накати цепочку на пустую БД и сравни `pg_dump -s`
с базой из полного `pgdesigner generate`.

Рискованные шаги `diff` помечает в stderr и комментарием в SQL:

- **`ENUM_ADD_VALUE`** — новое значение enum нельзя использовать до коммита транзакции. Если миграция тут же пишет это значение (`UPDATE`, `DEFAULT`), вынеси `ADD VALUE` в отдельную миграцию, у `/pgmigrator` — в предыдущий файл или `-NONTR.sql`.
- **`TABLE_REWRITE`** — новое выражение stored generated-колонки переписывает таблицу под блокировкой.
- **`COLUMN_RECREATE`** (dangerous) — обычная колонка становится generated через `DROP COLUMN` + `ADD COLUMN`: данные колонки пересчитываются, зависимые представления и FK блокируют `DROP`.
- **`TYPE_RECREATE`** (dangerous) — перестановка или удаление значения enum. SQL не выдаётся, только комментарий: PostgreSQL этого не умеет. Пиши руками (новый тип, `ALTER COLUMN … TYPE … USING`, `DROP TYPE` старого) или не меняй порядок.

### Сверка модели с живой базой

- **`convert` из базы без `-full`** читает таблицы и индексы, но не типы, представления, функции и триггеры — `diff` модели с таким файлом предлагает `DROP TYPE` для каждого enum. Для сверки — `convert -full`.
- **Граница партиции без смещения** (`'2024-01-01'`) база хранит в своей таймзоне (`'2024-01-01 00:00:00+03'`), и `diff` показывает ложный `REATTACH_PARTITION`. С явным смещением в модели ложной разницы нет.
- `convert "postgres://…"` пишет `<dbname>.pgd` и не перезаписывает существующий файл — задай `-o`. Пароль из DSN в сообщениях скрыт.

## SQL → PGD маппинг

| SQL | PGD |
|---|---|
| `CREATE TABLE` | `<table>` в нужную `<schema>` |
| `ALTER TABLE ADD COLUMN` | `<column>` в `<table>` |
| `CREATE INDEX` | `<index>` в `<schema>` (не в `<table>`) |
| `ADD CONSTRAINT` | `<pk>`/`<fk>`/`<unique>`/`<check>` в `<table>` |
| `CREATE TYPE` | `<enum>`/`<composite>`/`<domain>`/`<range>` в `<types>` |
| `CREATE FUNCTION` / `PROCEDURE` / `AGGREGATE` | `<function>` в `<functions>`, `kind="procedure"`/`"aggregate"` |
| `COMMENT ON TABLE/COLUMN` | атрибут `comment` у `<table>`/`<column>` |
| `UNLOGGED`, `TABLESPACE`, `USING` таблицы | атрибуты `unlogged`, `tablespace`, `using` у `<table>` |
| `WITH (…)`, `toast.*` | `<with><param name="toast.autovacuum_enabled" value="false"></param></with>` |

## Отличия от PDD (MicroOLAP)

| Аспект | PDD | PGD |
|---|---|---|
| Идентификация | числовые ID | имена |
| Типы | коды (25, 1043) | имена (`text`, `varchar`) |
| NOT NULL | `NotNull="1"` | `nullable="false"` |
| Индексы | внутри ENTITY | в `<schema>` |
| FK | секция REFERENCES | `<fk>` inline |
| Булевы | `"0"`/`"1"` | `"true"`/`"false"` |

## CLI `pgdesigner`

```bash
pgdesigner generate  [-o schema.sql] schema.pgd                   # DDL
pgdesigner diff      [-f json] [-o patch.sql] old.pgd new.pgd     # ALTER (используется в /pgmigrator), см. ловушки
pgdesigner lint      [-fix] [-s error] schema.pgd                 # 69 правил (E/W/I)
pgdesigner convert   [-o project.pgd] schema.pdd|.sql|.dbs|.dm2
pgdesigner convert   [-o project.pgd] [-schema s1,s2] -full "postgres://..."   # см. сверку с базой
pgdesigner testdata  [-seed 42 -rows 100] schema.pgd
pgdesigner merge     base.pgd overlay.pgd
```
