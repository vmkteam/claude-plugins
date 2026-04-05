---
name: pgd
description: "PGD — справочник по формату и CLI pgDesigner. Используй при работе с .pgd файлами."
---

# PGD — справочник по формату и CLI pgDesigner

Ты — эксперт по формату `.pgd` и CLI **pgDesigner** (pgdesigner.io). Используй это руководство при редактировании PGD-файлов и работе с CLI.

## Что такое PGD

`.pgd` — git-friendly XML-формат **pgDesigner** для описания схем PostgreSQL. Спецификация: https://pgdesigner.io/docs/pgd-format, валидация: `pgd-format.xsd`.

## Принципы формата

- **Без числовых ID** — объекты ссылаются по имени, кросс-схемные через `schema.table`
- **Git-friendly** — предсказуемый порядок элементов, атрибуты на одной строке
- **Сырой SQL в CDATA** — для CHECK, WHERE, тел функций, выражений
- **Булевы значения** — строки `"true"` / `"false"`

## Структура XML

```
<pgd version="1" pg-version="18" default-schema="public">
├── <project>              — имя, описание, настройки (naming, defaults, linting)
├── <database>             — имя БД, кодировка, коллация, шаблон
├── <roles>                — роли PostgreSQL
├── <tablespaces>          — физические расположения хранения
├── <extensions>           — расширения PG
├── <types>                — enum, composite, domain, range
├── <sequences>            — последовательности
├── <schema name="...">    — схемы (содержат таблицы и индексы)
│   ├── <table>            — таблицы
│   │   ├── <column>       — колонки
│   │   ├── <pk>           — PRIMARY KEY
│   │   ├── <fk>           — FOREIGN KEY
│   │   ├── <unique>       — UNIQUE
│   │   ├── <check>        — CHECK
│   │   ├── <exclude>      — EXCLUDE
│   │   ├── <with>         — параметры хранения
│   │   ├── <partition-by> — ключ партицирования
│   │   └── <partition>    — дочерние партиции
│   └── <index>            — индексы (на уровне схемы, НЕ внутри таблиц)
├── <views>                — представления (view, materialized-view)
├── <functions>            — функции, процедуры, агрегаты
├── <triggers>             — триггеры
├── <policies>             — RLS-политики
├── <comments>             — комментарии к объектам
├── <grants>               — привилегии
├── <rules>                — правила (deprecated)
└── <layouts>              — метаданные отображения (позиции, цвета, группы)
```

## Корневой элемент

```xml
<?xml version="1.0" encoding="UTF-8"?>
<pgd version="1" pg-version="18" default-schema="public">
  ...
</pgd>
```

| Атрибут | Обязательный | Описание |
|---------|-------------|----------|
| `version` | да | Версия формата (int), текущая: 1 |
| `pg-version` | нет | Целевая версия PostgreSQL (14-18) |
| `default-schema` | нет | Схема по умолчанию, default: `"public"` |

## Проект

```xml
<project name="myproject" description="My database">
  <settings>
    <naming convention="snake_case" tables="plural"></naming>
    <defaults nullable="true" on-delete="restrict"></defaults>
  </settings>
</project>
```

## Колонки (column)

```xml
<column name="email" type="varchar" length="255" nullable="false"
    default="''" collation="en_US.utf8" comment="User email"
    storage="extended" compression="lz4">
</column>
```

| Атрибут | Обязательный | Описание |
|---------|-------------|----------|
| `name` | да | Имя колонки |
| `type` | да | Тип данных PostgreSQL |
| `length` | нет | Длина (для varchar, char) |
| `precision` | нет | Точность (для numeric) |
| `scale` | нет | Масштаб (для numeric) |
| `nullable` | нет | default: `"true"`. `"false"` = NOT NULL |
| `default` | нет | SQL-выражение для DEFAULT |
| `collation` | нет | Коллация |
| `storage` | нет | plain, external, extended, main, default |
| `compression` | нет | lz4, pglz, default (PG14+) |
| `comment` | нет | Комментарий к колонке |

### IDENTITY колонки

```xml
<column name="id" type="bigint" nullable="false">
  <identity generated="always"></identity>
</column>
```

### Генерируемые колонки

```xml
<column name="full_name" type="text">
  <generated stored="true"><![CDATA[first_name || ' ' || last_name]]></generated>
</column>
```

## Типы данных

### Целые числа
`smallint`, `integer`, `bigint`

### Serial
`smallserial`, `serial`, `bigserial`

### Десятичные
`numeric`, `decimal`, `real`, `double precision`, `money`

### Символьные
`varchar` / `character varying`, `char` / `character`, `text`

### Дата/время
`date`, `time`, `timetz`, `timestamp`, `timestamptz`, `interval`

### Прочие
`boolean`, `uuid`, `json`, `jsonb`, `xml`, `bytea`, `inet`, `cidr`, `macaddr`, `tsvector`, `tsquery`, `bit`, `varbit`

### Массивы
Суффикс `[]`: `text[]`, `integer[]`, `jsonb[]`

### Диапазоны (PG14+)
`int4range`, `int8range`, `numrange`, `tsrange`, `tstzrange`, `daterange`

### Пользовательские типы
Ссылка по имени: `status`, или с квалификацией схемы: `myschema.status`

## Пользовательские типы (types)

### Enum
```xml
<enum name="user_status" schema="public">
  <label>active</label>
  <label>inactive</label>
  <label>banned</label>
</enum>
```

### Composite
```xml
<composite name="address" schema="public">
  <field name="street" type="text"></field>
  <field name="city" type="varchar" length="100"></field>
</composite>
```

### Domain
```xml
<domain name="email_addr" schema="public" type="varchar" length="255" default="''">
  <check name="email_check"><![CDATA[VALUE ~ '^.+@.+$']]></check>
</domain>
```

### Range
```xml
<range name="float_range" schema="public" subtype="float8"></range>
```

## Constraints (ограничения)

### PRIMARY KEY

```xml
<pk name="pk_users" deferrable="false">
  <column name="id"></column>
</pk>
```

Составной PK:
```xml
<pk name="pk_user_roles">
  <column name="user_id"></column>
  <column name="role_id"></column>
</pk>
```

### FOREIGN KEY

```xml
<fk name="fk_orders_user" to-table="users"
    on-delete="cascade" on-update="no action"
    deferrable="false" match="simple">
  <column name="user_id" references="id"></column>
</fk>
```

### UNIQUE

```xml
<unique name="uq_users_email" nulls-distinct="true">
  <column name="email"></column>
</unique>
```

### CHECK

```xml
<check name="chk_age"><![CDATA[age >= 0 AND age < 200]]></check>
```

### EXCLUDE

```xml
<exclude name="excl_booking" using="gist">
  <element column="room_id" with="="></element>
  <element column="period" with="&&"></element>
</exclude>
```

## Индексы (index)

**Важно:** индексы определяются на уровне `<schema>`, а НЕ внутри `<table>`.

```xml
<index name="idx_users_email" table="users" unique="true" using="btree">
  <column name="email" order="asc" nulls="last"></column>
</index>
```

### Индекс по выражению

```xml
<index name="idx_users_lower_email" table="users" using="btree">
  <expression><![CDATA[lower(email)]]></expression>
</index>
```

### Partial index (WHERE)

```xml
<index name="idx_active_users" table="users" using="btree">
  <column name="email"></column>
  <where><![CDATA[deleted_at IS NULL]]></where>
</index>
```

### Covering index (INCLUDE, PG11+)

```xml
<index name="idx_users_email_incl" table="users" unique="true">
  <column name="email"></column>
  <include>
    <column name="name"></column>
  </include>
</index>
```

## Партицирование

```xml
<table name="events">
  <column name="id" type="bigint" nullable="false"></column>
  <column name="created_at" type="timestamptz" nullable="false"></column>
  <pk name="pk_events">
    <column name="id"></column>
    <column name="created_at"></column>
  </pk>
  <partition-by type="range">
    <column name="created_at"></column>
  </partition-by>
  <partition name="events_2024">
    <bound>FOR VALUES FROM ('2024-01-01') TO ('2025-01-01')</bound>
  </partition>
</table>
```

## Сценарий: SQL-миграция → изменения в PGD

| SQL-операция | Что менять в PGD |
|---|---|
| `CREATE TABLE` | Добавить `<table>` в нужную `<schema>` |
| `ALTER TABLE ADD COLUMN` | Добавить `<column>` в существующий `<table>` |
| `CREATE INDEX` | Добавить `<index>` в `<schema>` (НЕ внутрь `<table>`) |
| `ALTER TABLE ADD CONSTRAINT` | Добавить `<pk>` / `<fk>` / `<unique>` / `<check>` в `<table>` |
| `CREATE TYPE` | Добавить `<enum>` / `<composite>` / `<domain>` в `<types>` |
| `CREATE FUNCTION` | Добавить `<function>` в `<functions>` |

Порядок элементов внутри `<table>`: columns → pk → fk → unique → check → exclude → with → partition-by → partition.

## Ключевые отличия от PDD (MicroOLAP)

| Аспект | PDD (MicroOLAP) | PGD (pgDesigner) |
|--------|-----------------|-------------------|
| Идентификация | Числовые ID | Имена объектов |
| Типы данных | Коды (25, 1043...) | Имена (`text`, `varchar`) |
| NOT NULL | `NotNull="1"` | `nullable="false"` |
| Индексы | Внутри ENTITY | На уровне schema |
| FK | Отдельная секция REFERENCES | `<fk>` внутри table |
| Булевы | `"0"` / `"1"` | `"true"` / `"false"` |

## CLI (pgdesigner)

Синтаксис: `pgdesigner [command] [flags] <file>`

### generate — генерация DDL
```bash
pgdesigner generate schema.pgd                  # в stdout
pgdesigner generate -o schema.sql schema.pgd     # в файл
```

### diff — сравнение схем и генерация ALTER
```bash
pgdesigner diff old.pgd new.pgd                  # ALTER SQL в stdout
pgdesigner diff -f json old.pgd new.pgd           # JSON-формат различий
```

### lint — валидация схемы (75 правил)
```bash
pgdesigner lint schema.pgd                        # текстовый отчёт
pgdesigner lint -fix schema.pgd                   # автоисправление
```

### convert — импорт из других форматов
```bash
pgdesigner convert schema.pdd -o project.pgd                    # из MicroOLAP PDD
pgdesigner convert schema.sql -o project.pgd                    # из pg_dump SQL
pgdesigner convert "postgres://localhost/mydb" -o project.pgd   # из живой БД
```

### testdata — генерация тестовых данных
```bash
pgdesigner testdata schema.pgd                              # 50 строк на таблицу
pgdesigner testdata -seed 42 -rows 100 schema.pgd           # воспроизводимые данные
```

## Рекомендации

1. **Индексы — на уровне `<schema>`**, не внутри `<table>`
2. **Используй CDATA** для SQL-выражений в CHECK, WHERE, телах функций
3. **Порядок элементов** внутри `<table>`: columns → pk → fk → unique → check → exclude
4. **Не нужны числовые ID** — объекты идентифицируются по имени
5. **Кросс-схемные ссылки** через точечную нотацию: `schema.table`
6. **nullable по умолчанию `"true"`** — для NOT NULL явно указывай `nullable="false"`
