---
name: scaffold
description: "Scaffold — создание нового Go-сервиса из шаблона gold-apisrv. Используй когда нужно завести новый сервис с нуля (репо, структура, Makefile, CI, конфиг, main)."
---

# Scaffold — создание нового Go-сервиса

Создание нового проекта из шаблона vmkteam/gold-apisrv (https://github.com/vmkteam/gold-apisrv).

## Триггер

- "создай новый сервис"
- "bootstrap проект"
- "новый API сервер"

## Входные данные

Спроси у пользователя:
1. **Имя проекта** (module name, например `reviewsrv`, `ordersrv`)
2. **Имя бизнес-слоя** (может отличаться от проекта, например проект `ordersrv` → бизнес-слой `orders`). По умолчанию = имя проекта без суффикса `srv`
3. **Путь** куда клонировать (по умолчанию `~/{workspace}/{name}/`)
4. **Порт** (по умолчанию 8075)
5. **База данных** (имя и PostgreSQL-схема, по умолчанию имя = проект, схема = `public`)
6. **Нужен ли VT** (admin CRUD API, по умолчанию да)
7. **Нужен ли VFS** (файловое хранилище, по умолчанию нет)

## Алгоритм

### Шаг 1. Клонировать и инициализировать

```bash
git clone https://github.com/vmkteam/gold-apisrv.git {path}/{name}
cd {path}/{name}
rm -rf .git
git init
```

### Шаг 2. make init

В шаблоне есть `make init` который выполняет начальную настройку, включая генерацию `Makefile.mk` из `Makefile.mk.dist`. Запустить:

```bash
make init
```

`Makefile.mk` — локальный конфиг проекта (переменные, пути), подключается из основного `Makefile`. Находится в `.gitignore`.

### Шаг 3. Переименовать модуль и проект

```bash
# go.mod
sed -i '' 's/module apisrv/module {name}/' go.mod

# Все импорты в .go файлах
find . -name '*.go' -not -path './vendor/*' -exec sed -i '' 's|"apisrv/|"{name}/|g' {} +
```

Файлы для правки:

| Файл | Что менять |
|------|-----------|
| `cmd/apisrv/main.go` | `const appName = "apisrv"` → `"{name}"` |
| `Makefile` | `NAME := apisrv` → `NAME := {name}` |
| `Makefile` | `PGDATABASE ?= apisrv` → `PGDATABASE ?= {name}` |
| `Makefile` | `TEST_PGDATABASE ?= test-apisrv` → `TEST_PGDATABASE ?= test-{name}` |
| `deployments/Dockerfile` | `CI_PROJECT_NAME=apisrv` → `CI_PROJECT_NAME={name}` |
| `cfg/local.toml.dist` | `Database = "apisrv"` → `Database = "{name}"` |

### Шаг 4. Переименовать директории и файлы

```bash
mv cmd/apisrv cmd/{name}
mv docs/model/apisrv.mfd docs/model/{name}.mfd
mv docs/apisrv.sql docs/{name}.sql
mv docs/apisrv.pgd docs/{name}.pgd 2>/dev/null

# Обновить ссылки в Makefile
sed -i '' 's/apisrv\.mfd/{name}.mfd/g' Makefile
```

### Шаг 5. Бизнес-слой (если имя отличается от проекта)

Если бизнес-слой называется иначе (например `billing` вместо `order`):

```bash
# Переименовать domain-пакет если существует
mv pkg/apisrv pkg/{domain_name} 2>/dev/null

# Обновить импорты
find . -name '*.go' -not -path './vendor/*' -exec sed -i '' 's|"{name}/pkg/apisrv"|"{name}/pkg/{domain_name}"|g' {} +
```

### Шаг 6. VT (если не нужен)

Если VT не нужен — удалить:
```bash
rm -rf pkg/vt/
# Убрать registerVTApiHandlers из pkg/app/handlers.go
# Убрать VT-импорты из pkg/app/app.go
```

### Шаг 7. Конфигурация

```bash
cp cfg/local.toml.dist cfg/local.toml
```

Обновить в `cfg/local.toml`:
- `Port = {port}`
- `Database = "{name}"`
- `EnableVFS = {true/false}`

### Шаг 8. MFD-файл

В `docs/model/{name}.mfd`:
```xml
<Name>{name}.mfd</Name>
```

### Шаг 9. База данных и сборка

```bash
make db        # создать БД и загрузить схему
make db-test   # создать тестовую БД
make mod       # go mod tidy && go mod vendor
make build     # скомпилировать
make run       # запустить в dev-режиме
```

### Шаг 10. Проверка

```bash
curl http://localhost:{port}/status
curl http://localhost:{port}/v1/rpc/
curl http://localhost:{port}/metrics
```

## Структура нового проекта

```
{name}/
├── Makefile                  # основной (include Makefile.mk)
├── Makefile.mk               # локальные переменные (gitignored)
├── cmd/{name}/main.go        # точка входа
├── pkg/
│   ├── app/                   # App, handlers, metrics, config
│   ├── db/                    # ORM-модели, репозитории
│   ├── {domain_name}/         # Domain (бизнес-логика, если нужна)
│   ├── rpc/                   # Публичный API
│   └── vt/                    # Admin API (если нужен)
├── docs/
│   ├── {name}.sql             # DDL
│   ├── {name}.pgd             # Схема pgDesigner
│   ├── init.sql               # seed data
│   ├── patches/               # Миграции (pgmigrator)
│   └── model/{name}.mfd       # MFD-схема
├── cfg/
│   ├── local.toml             # конфиг (gitignored)
│   └── local.toml.dist        # шаблон конфига
├── deployments/Dockerfile
└── go.mod
```

## Работа с БД по стадиям

### Стадия "Идея" (нет devel-окружения)

`docs/{name}.sql` — **всегда актуальный**. Это source of truth. Миграций нет.

При изменении схемы:
1. Редактировать `docs/{name}.pgd` → `pgdesigner generate` → обновить `docs/{name}.sql`
2. `make db` — пересоздать БД с нуля
3. `make mfd-xml && make mfd-model` — перегенерировать Go-код

### Стадия "Dev" (появился devel)

Нельзя пересоздать БД на devel → **появляются миграции** в `docs/patches/`.

При изменении схемы:
1. Написать миграцию в `docs/patches/` (/pgmigrator)
2. Обновить `docs/{name}.sql` (держать в актуальном состоянии)
3. `pgmigrator run` на devel
4. `make mfd-xml && make mfd-model`

## Следующие шаги после scaffold

1. Спроектировать схему БД → /pgd
2. Сгенерировать SQL → `pgdesigner generate`
3. `make db` → `make mfd-xml` → `make mfd-model` → /mfd
4. Добавить RPC-сервисы → /zenrpc
5. Добавить VT CRUD (если нужен) → /mfd (`make mfd-vt-rpc NS=...`)
6. Онбординг в системы → /onboard
