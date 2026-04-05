---
name: pgmdd
description: "PDD — справочник по формату MicroOLAP Database Designer. Используй при редактировании PDD-файлов."
---

# PDD — справочник по формату MicroOLAP Database Designer

Ты — эксперт по формату `.pdd` (MicroOLAP Database Designer for PostgreSQL). Используй это руководство при редактировании PDD-файлов.

## Что такое PDD

`.pdd` — проприетарный XML-формат **MicroOLAP Database Designer for PostgreSQL** (MDD). Публичной спецификации нет.

## Структура XML

```
DBMODEL
├── MODELSETTINGS          — версия, настройки
├── DATABASE               — имя БД
├── ROLES                  — роли PostgreSQL
├── SCHEMAS                — схемы
├── COMPOSITES             — записи-типы (по одной на таблицу)
├── METADATA
│   ├── ENTITIES           — таблицы
│   │   ├── COLUMNS        — колонки
│   │   ├── CONSTRAINTS    — PK, UNIQUE
│   │   └── INDEXES        — индексы
│   ├── REFERENCES         — FK-связи
│   └── ...
└── ...
```

## Типы данных (Datatype)

| PostgreSQL | Datatype | Type | Width |
|------------|----------|------|-------|
| `text` | 25 | `text` | 0 |
| `varchar(N)` | 1043 | `varchar` | N |
| `int4` | 23 | `int4` | 0 |
| `int8` | 20 | `int8` | 0 |
| `float4` | 700 | `float4` | 0 |
| `float8` | 701 | `float8` | 0 |
| `bool` | 16 | `bool` | 0 |
| `text[]` | 1009 | `text[]` | 0 |
| `int4[]` | 1007 | `int4[]` | 0 |
| `jsonb` | 3802 | `jsonb` | 0 |
| `timestamptz` | 1184 | `timestamp with time zone` | -1 |

## Колонки (COLUMN)

```xml
<COLUMN ID="1428002" Name="filename" Pos="2"
    Datatype="25" Type="text" Width="0" Prec="0"
    NotNull="1" AutoInc="0" PrimaryKey="0" IsFKey="0"
    DefaultValue="..." QuoteDefault="0" Comments="">
</COLUMN>
```

| Атрибут | Значение | Описание |
|---------|----------|----------|
| `NotNull` | 0/1 | NOT NULL |
| `PrimaryKey` | 0/1 | Входит в PK |
| `AutoInc` | 0/2/3 | 0=нет, 2=ALWAYS IDENTITY, 3=BY DEFAULT IDENTITY |
| `QuoteDefault` | 0/1 | 0=выражение, 1=строковый литерал |

### DefaultValue

| SQL DEFAULT | DefaultValue | QuoteDefault |
|-------------|-------------|--------------|
| _(нет)_ | `""` | `0` |
| `DEFAULT ''` | `"''"` | `0` |
| `DEFAULT 0` | `"0"` | `0` |
| `DEFAULT '{}'` | `"{}"` | `1` |
| `DEFAULT NOW()` | `"NOW()"` | `0` |

### Экранирование

| Символ | Escape |
|--------|--------|
| `'` | `\a` |
| `"` | `\A` |

## Constraints

- `Kind="2"` — PRIMARY KEY
- `Kind="1"` — UNIQUE
- `COMMATEXT` — ID колонок через запятую

## Индексы

```xml
<INDEX ID="70222" Name="idx_nvts_family" Unique="0" Method="0">
    <INDEXCOLUMNS COMMATEXT="family"></INDEXCOLUMNS>
</INDEX>
```

| Method | PostgreSQL |
|--------|-----------|
| 0 | btree |
| 4 | GIST |
| 5 | GIN |

- `Predicate` для partial index (`"` экранируется как `\A`)
- INDEXCOLUMNS содержит **имена** колонок (не ID)

## Добавление новой таблицы

1. Найти максимальные ID в файле
2. Добавить COMPOSITE с `MasterTableOID` = ID нового ENTITY
3. Добавить ENTITY с COLUMNS, CONSTRAINTS, INDEXES
4. Обязательно открыть и пересохранить в MDD GUI

## Рекомендации

1. **Всегда пересохраняй в MDD GUI** после ручного редактирования
2. **ID уникальны** в пределах файла
3. **Для DEFAULT ''** — `DefaultValue="''" QuoteDefault="0"`
4. **Для GIN** — `Method="5"` (не 4, это GIST)
5. Проверяй Generate Script в MDD после изменений
