---
name: pgmdd
description: "PDD — справочник по формату MicroOLAP Database Designer. Используй при редактировании PDD-файлов."
---

# PDD — MicroOLAP Database Designer формат

`.pdd` — проприетарный XML [MicroOLAP Database Designer for PostgreSQL](https://microolap.com/products/database/designer-for-postgresql/). Публичной спецификации нет — ориентируйся на существующие файлы в `docs/`.

Для новых проектов предпочитай PGD (см. `/pgd`). PDD — legacy-формат.

## Non-obvious правила

- **Числовые ID уникальны в пределах файла** — при добавлении объекта сначала найди max(ID)
- **После ручной правки — ВСЕГДА открой и пересохрани в MDD GUI**, иначе Generate Script сломается
- **COMPOSITE на каждую таблицу** — запись-тип с `MasterTableOID` = ID ENTITY; без неё таблица не видна в GUI
- **INDEXCOLUMNS — имена, не ID** колонок (через `COMMATEXT`)
- **`"` в Predicate экранируется как `\A`**, `'` — как `\a`
- **GIN = `Method="5"`**, GIST = `Method="4"` (легко перепутать)
- **DEFAULT пустая строка:** `DefaultValue="''" QuoteDefault="0"` (выражение, не литерал)

## Иерархия

```
DBMODEL
├── MODELSETTINGS, DATABASE, ROLES, SCHEMAS
├── COMPOSITES              запись-тип на каждую таблицу
└── METADATA
    ├── ENTITIES            таблицы
    │   ├── COLUMNS
    │   ├── CONSTRAINTS     PK (Kind=2), UNIQUE (Kind=1)
    │   └── INDEXES         внутри ENTITY (в отличие от PGD!)
    └── REFERENCES          FK отдельной секцией
```

## Типы (Datatype коды)

| PG | Datatype | Type | Width |
|---|---|---|---|
| text | 25 | text | 0 |
| varchar(N) | 1043 | varchar | N |
| int4 | 23 | int4 | 0 |
| int8 | 20 | int8 | 0 |
| float4 | 700 | float4 | 0 |
| float8 | 701 | float8 | 0 |
| bool | 16 | bool | 0 |
| jsonb | 3802 | jsonb | 0 |
| timestamptz | 1184 | timestamp with time zone | -1 |
| text[] | 1009 | text[] | 0 |
| int4[] | 1007 | int4[] | 0 |

## COLUMN

```xml
<COLUMN ID="1428002" Name="filename" Pos="2"
    Datatype="25" Type="text" Width="0" Prec="0"
    NotNull="1" AutoInc="0" PrimaryKey="0" IsFKey="0"
    DefaultValue="" QuoteDefault="0" Comments=""/>
```

- `NotNull`/`PrimaryKey`/`IsFKey` — 0/1
- `AutoInc` — 0=нет, 2=ALWAYS IDENTITY, 3=BY DEFAULT IDENTITY
- `QuoteDefault` — 0=выражение (NOW(), 0, ''), 1=строковый литерал ({}, текст)

## INDEX

```xml
<INDEX ID="70222" Name="idx_nvts_family" Unique="0" Method="0">
    <INDEXCOLUMNS COMMATEXT="family"/>
</INDEX>
```

`Method`: 0=btree, 4=GIST, 5=GIN. Partial — атрибут `Predicate`.

## Добавление новой таблицы

1. Найти max ID в файле
2. ENTITY + COLUMNS + CONSTRAINTS + INDEXES с новыми ID
3. COMPOSITE с `MasterTableOID` = ID нового ENTITY
4. Открыть и пересохранить в MDD GUI
5. Проверить Generate Script
