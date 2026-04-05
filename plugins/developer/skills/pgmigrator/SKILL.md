---
name: pgmigrator
description: "pgmigrator — инструмент SQL миграций PostgreSQL. Используй при создании и применении миграций."
---

# pgmigrator — SQL миграции PostgreSQL

pgmigrator (https://github.com/vmkteam/pgmigrator) — CLI для инкрементальных миграций PostgreSQL. Отслеживает выполненные миграции в таблице `public.pgMigrations`.

## Установка

```bash
brew tap vmkteam/tap
brew install pgmigrator
# или
make tools  # в проектах vmkteam
```

Docker: `vmkteam/pgmigrator` на Docker Hub.

## Конфигурация

Обычно лежит рядом с миграциями, например `docs/patches/pgmigrator.toml`:

```toml
[App]
Table = "public.pgMigrations"
StatementTimeout = "5s"
FileMask = "\\d{4}-\\d{2}-\\d{2}-\\S+.sql"

[Database]
Addr = "localhost:5432"
User = "postgres"
Database = "dbname"
Password = "postgres"
PoolSize = 1
ApplicationName = "pgmigrator"
```

## Расположение миграций

Типичная структура — `docs/patches/`:

```
docs/patches/
├── pgmigrator.toml
├── 2024/                                  # старые, по годам
├── 2025/
│   ├── 2025-01-14-dummy.sql
│   └── 2025-02-10-IX_orders-MANUAL.sql
├── 2026-01-29-rfmUsers.sql                # транзакционная
├── 2026-02-01-add-index-NONTR.sql         # нетранзакционная
└── 2026-02-03-add-partitions-MANUAL.sql   # ручная
```

## Формат файлов

Имя: `YYYY-MM-DD-<description>.sql`. Применяются в алфавитном порядке.

| Суффикс | Поведение |
|---------|-----------|
| `.sql` | Транзакционная (BEGIN/COMMIT автоматически) |
| `-NONTR.sql` | Без транзакции (для CREATE INDEX CONCURRENTLY) |
| `-MANUAL.sql` | Игнорируется pgmigrator (ручное применение DBA) |

**MANUAL** — для операций которые нельзя автоматизировать: партиции, тяжёлые индексы на больших таблицах, миграции с downtime.

## Команды

| Команда | Описание |
|---------|----------|
| `pgmigrator plan` | Показать миграции к применению |
| `pgmigrator run` | Применить все новые |
| `pgmigrator run 1` | Применить N миграций |
| `pgmigrator dryrun` | Тест с откатом |
| `pgmigrator skip` | Пометить выполненными без запуска |
| `pgmigrator last` | Последние применённые |
| `pgmigrator verify` | Проверить целостность (MD5) |
| `pgmigrator redo` | Перезапустить последнюю |
| `pgmigrator init` | Создать пример конфига |

Флаги: `-c, --config` (путь к конфигу), `-d, --dir` (директория миграций).

## Makefile

```makefile
db-migrate:
	@pgmigrator --config docs/patches/pgmigrator.toml run
```

## Примеры миграций

### Транзакционная — новая таблица

```sql
-- 2026-01-29-rfmUsers.sql
CREATE TABLE "rfmUsers" (
    "siteUserId" int4 NOT NULL,
    "rfmSegmentApp" varchar(20) NOT NULL,
    "updatedAt" timestamp with time zone NOT NULL DEFAULT now(),
    PRIMARY KEY("siteUserId")
);

ALTER TABLE "rfmUsers" ADD CONSTRAINT "Ref_rfmUsers_to_siteUsers"
    FOREIGN KEY ("siteUserId") REFERENCES "siteUsers"("siteUserId")
    MATCH SIMPLE ON DELETE NO ACTION ON UPDATE NO ACTION NOT DEFERRABLE;
```

### Нетранзакционная — индекс

```sql
-- 2025-02-10-IX_orders_isActive-NONTR.sql
create index concurrently "IX_orders_isActive" on orders ("siteUserId")
    where "statusId" IN (7, 4, 9, 10)
        and "params"->>'isCompletedByUser' is distinct from 'true';
```

### MANUAL — партиции

```sql
-- 2026-02-03-add-orders-210kk_220kk-partitions-MANUAL.sql
create table orders_210kk_220kk (like orders including all);
alter table orders attach partition orders_210kk_220kk
    for values from (210000000) to (220000000);
analyse orders_210kk_220kk;
```

## Безопасные операции

| Операция | Безопасно? | Комментарий |
|----------|-----------|-------------|
| CREATE TABLE | Да | Не блокирует |
| ADD COLUMN (nullable) | Да | Быстро |
| ADD COLUMN (NOT NULL + DEFAULT) | PG11+ Да | На уровне каталога |
| DROP COLUMN | Да | Пометка в каталоге |
| CREATE INDEX | **Нет** | Блокирует → используй NONTR |
| CREATE INDEX CONCURRENTLY | Да | `-NONTR.sql` |
| ADD CONSTRAINT ... NOT VALID | Да | Не проверяет существующие |
| VALIDATE CONSTRAINT | Да | ShareUpdateExclusiveLock |
| Партиции (ATTACH/DETACH) | Зависит | `-MANUAL.sql` |

## Когда нужны миграции

- **Стадия "Идея"** (нет devel) — миграций нет. `docs/{name}.sql` всегда актуальный, `make db` пересоздаёт с нуля.
- **Стадия "Dev+"** (есть devel-окружение) — появляются миграции в `docs/patches/`, потому что нельзя пересоздать БД на devel.

При этом `docs/{name}.sql` всегда держится в актуальном состоянии (и миграция, и основной файл обновляются).

## Workflow

### Новая таблица

1. Спроектировать в pgDesigner (/pgd) или MicroOLAP (/pgmdd)
2. Написать `.sql` в `docs/patches/`
3. Индексы → отдельный `-NONTR.sql`
4. `pgmigrator dryrun` на dev
5. `pgmigrator run`
6. `make mfd-xml` → `make mfd-model` → `make mfd-repo NS=<ns>` (/mfd)

### Перед деплоем

- `pgmigrator dryrun` на staging
- Нет блокирующих ALTER на больших таблицах
- CONCURRENTLY → `-NONTR.sql`, партиции → `-MANUAL.sql`
- `pgmigrator verify` — MD5 целостность
