---
name: pgd
description: "PGD — справочник по формату и CLI pgDesigner. Используй при работе с .pgd файлами."
---

# PGD — pgDesigner формат и CLI

`.pgd` — git-friendly XML-формат [pgDesigner](https://pgdesigner.io) для схем PostgreSQL.
Полная спецификация: https://pgdesigner.io/docs/pgd-format (XSD: `pgd-format.xsd`).

CLI: `pgdesigner` (не `pgd`).

## Non-obvious правила редактирования

- **Без числовых ID** — объекты по имени; кросс-схемно через `schema.table`
- **`<index>` — на уровне `<schema>`, НЕ внутри `<table>`** (частая ошибка при конверсии из PDD)
- **Порядок элементов в `<table>` ломает диф:** columns → pk → fk → unique → check → exclude → with → partition-by → partition
- **Булевы — строки** `"true"`/`"false"` (не `"0"`/`"1"` как в PDD)
- **SQL всегда в CDATA** — CHECK, WHERE, тела функций, generated-выражения, bound партиций
- **`nullable` default `"true"`** — для NOT NULL ставь явно `nullable="false"`
- Атрибуты на одной строке — иначе git-diff будет шумный

## Корень

```xml
<?xml version="1.0" encoding="UTF-8"?>
<pgd version="1" pg-version="18" default-schema="public">
```

## Иерархия

```
<pgd>
├── <project>/<settings>     naming, defaults, linting
├── <database>               имя, кодировка, коллация
├── <roles> <tablespaces> <extensions>
├── <types>                  enum, composite, domain, range
├── <sequences>
├── <schema>
│   ├── <table>
│   │   └── column, pk, fk, unique, check, exclude, with,
│   │       partition-by, partition
│   └── <index>              <-- на уровне schema!
├── <views> <functions> <triggers> <policies>
├── <comments> <grants> <rules>
└── <layouts>                позиции/цвета редактора
```

## Канонические сниппеты

Enum (редактор восстанавливает порядок `<label>` — ручная перестановка не ломает):
```xml
<enum name="user_status" schema="public">
  <label>active</label>
  <label>inactive</label>
</enum>
```

FK (inline в `<table>`, в отличие от PDD):
```xml
<fk name="fk_orders_user" to-table="users" on-delete="cascade" on-update="no action">
  <column name="user_id" references="id"></column>
</fk>
```

Индекс по выражению / partial / covering:
```xml
<index name="idx_users_lower_email" table="users" using="btree">
  <expression><![CDATA[lower(email)]]></expression>
  <where><![CDATA[deleted_at IS NULL]]></where>
  <include><column name="name"></column></include>
</index>
```

IDENTITY и generated:
```xml
<column name="id" type="bigint" nullable="false">
  <identity generated="always"></identity>
</column>
<column name="full_name" type="text">
  <generated stored="true"><![CDATA[first_name || ' ' || last_name]]></generated>
</column>
```

Партицирование:
```xml
<partition-by type="range"><column name="created_at"></column></partition-by>
<partition name="events_2024">
  <bound>FOR VALUES FROM ('2024-01-01') TO ('2025-01-01')</bound>
</partition>
```

Полный синтаксис всех тегов и атрибутов: https://pgdesigner.io/docs/pgd-format.

## SQL → PGD маппинг

| SQL | PGD |
|---|---|
| `CREATE TABLE` | `<table>` в нужную `<schema>` |
| `ALTER TABLE ADD COLUMN` | `<column>` в `<table>` |
| `CREATE INDEX` | `<index>` в `<schema>` (не в `<table>`) |
| `ADD CONSTRAINT` | `<pk>`/`<fk>`/`<unique>`/`<check>` в `<table>` |
| `CREATE TYPE` | `<enum>`/`<composite>`/`<domain>` в `<types>` |
| `CREATE FUNCTION` | `<function>` в `<functions>` |

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
pgdesigner generate  schema.pgd [-o schema.sql]          # DDL
pgdesigner diff      old.pgd new.pgd [-f json]           # ALTER (используется в /pgmigrator)
pgdesigner lint      schema.pgd [-fix]                   # 75 правил
pgdesigner convert   schema.pdd|schema.sql|"postgres://..." -o project.pgd
pgdesigner testdata  schema.pgd [-seed 42 -rows 100]
```
