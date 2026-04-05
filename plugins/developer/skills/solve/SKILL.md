---
name: solve
description: "Solve — решение задачи из YouTrack. Полный цикл: анализ → план → реализация → ревью → коммит с артефактами."
---

# /solve — решение задачи

Полный цикл решения задачи из YouTrack с human-in-the-loop на ключевых этапах.
Подключения к системам из `.claude/memory/project-index.md`.

## Использование

```
/solve PLF-819
/solve WEB-456
```

## Артефакты

Каждый этап создаёт документ в `docs/llm/tasks/{TASK_ID}/`:

```
docs/llm/tasks/PLF-819/
├── research.md      — анализ задачи, контекст, вопросы (шаг 2)
├── spec.md          — спецификация плана реализации (шаг 3)
├── review-initial.md      — первое ревью (шаг 9)
└── review-final.md  — финальное ревью перед коммитом (шаг 9, повторное)
```

## Flow

```
FETCH → ANALYZE → research.md → ⏸ HITL
                                     ↓ утвердили
                                PLAN → spec.md → ⏸ HITL
                                                     ↓ утвердили
                                                TEST → IMPLEMENT → SIMPLIFY → FMT+LINT → VERIFY → REVIEW → ⏸ HITL → COMMIT → ⏸ HITL → YOUTRACK → ⏸ HITL
```

**Важно:**
- PLAN начинается только после утверждения research
- IMPLEMENT — только после утверждения spec
- REVIEW (/go-review) — всегда, без исключений

---

### 1. FETCH — прочитать задачу

Получить задачу из YouTrack (скилл /youtrack):

```bash
pcurl @{yt_profile} 'https://{yt_host}/api/issues/{TASK_ID}?fields=idReadable,summary,description,created,updated,reporter(login,name),assignee(login,name),tags(name),comments(author(login),text,created),customFields(name,value(name))' -s
```

Извлечь:
- Summary и description
- Комментарии (могут содержать уточнения)
- Тип задачи (Bug, Task, Feature)
- Приоритет

Создать директорию: `mkdir -p docs/llm/tasks/{TASK_ID}/`

**Аттачи:**
```bash
# Получить список аттачей
pcurl @{yt_profile} 'https://{yt_host}/api/issues/{TASK_ID}/attachments?fields=id,name,url,mimeType,size,created,author(login)' -s
```

Для каждого аттача с поддерживаемым типом (image/*, application/pdf):
```bash
pcurl @{yt_profile} 'https://{yt_host}{url}' -s -o docs/llm/tasks/{TASK_ID}/{filename}
```

Скачанные изображения и PDF — прочитать и проанализировать (Claude видит картинки и PDF).
Остальные форматы — упомянуть в research.md без скачивания.

### 2. ANALYZE — анализ контекста (plan mode)

Войти в plan mode для анализа и планирования. Не писать код до утверждения spec.

На основе задачи:

**Контекст из YouTrack:**
- Получить связанные задачи (parent, subtasks, linked issues):
  ```bash
  pcurl @{yt_profile} 'https://{yt_host}/api/issues/{TASK_ID}?fields=idReadable,summary,links(direction,linkType(name),issues(idReadable,summary,resolved))' -s
  ```
- Прочитать связанные задачи для полного контекста
- Сохранить контекст связанных задач в артефакт если объёмный

**Контекст из git-истории:**
- Найти коммиты по номеру задачи и связанным задачам:
  ```bash
  git log --oneline --all --grep="{TASK_ID}" | head -20
  git log --oneline --all --grep="{PARENT_ID}" | head -20
  ```
- Понять кто работал с этим кодом, как проект развивался
- Изучить предыдущие изменения в затронутых файлах:
  ```bash
  git log --oneline -10 -- {file}
  ```

**Анализ кода:**
- Определить какие файлы/пакеты затронуты
- Прочитать релевантный код
- Если фича — определить scope изменений
- Проверить связанные тесты

**Если баг — Root Cause Analysis:**

Определить глубину расследования по описанию бага:

| Признаки | Уровень | Что делать |
|----------|---------|-----------|
| Ясная ошибка в коде, stacktrace в описании | **Лёгкий** | Sentry (поиск по ключевым словам) + git log + чтение кода |
| Непонятная причина, "иногда не работает", деградация | **Полный** | Вызвать `/investigate` как подшаг — Sentry + Prometheus + Loki + API проверка на dev/prod |

Лёгкий (код + Sentry):
```bash
# Sentry: поиск по ключевым словам из описания бага
pcurl @{sentry_profile} 'https://{sentry_host}/api/0/organizations/{org}/issues/?query=is:unresolved+{keywords}&sort=freq&statsPeriod=7d&limit=5' -s
```

Полный (вызвать /investigate):
- Sentry — ошибки и stacktrace
- Prometheus — error rate, latency аномалии за период
- Loki — логи с ошибками по методу/endpoint
- API — воспроизвести запрос на dev, проверить на prod
- Сравнить задеплоенную версию с кодом (Sentry release commit)

**Артефакт:** Сохранить `docs/llm/tasks/{TASK_ID}/research.md`:

```markdown
# {TASK_ID} — Research

## Задача
- **Summary:** {summary}
- **Тип:** {Bug/Task/Feature}
- **Приоритет:** {priority}
- **Описание:** {description}

## Аттачи
- {filename} ({mimeType}, {size}) — {что на картинке / краткое содержание PDF}
- {filename} — не анализировался ({mimeType})

## Связанные задачи
- **Parent:** {parent_id} — {summary}
- **Subtasks:** {list}
- **Linked:** {list с типом связи}

## История (git)
- Предыдущие коммиты по теме: {список}
- Последние изменения в затронутых файлах: {кто, когда, что}

## Анализ
- **Понимание:** {1-2 предложения}
- **Scope изменений:** {краткий список}

## Root Cause (если баг)
- **Уровень расследования:** {лёгкий/полный}
- **Причина:** {описание}
- **Sentry:** {issue_id, stacktrace, count events}
- **Prometheus:** {error rate, latency — если полный}
- **Loki:** {релевантные логи — если полный}
- **Воспроизводимость:** {dev/prod, шаги}

## Затронутые файлы
- {file:line} — {почему}

## Вопросы
- {вопрос 1}

## Риски
- {риск 1}
```

### ⏸ HITL: Утверждение research

Показать пользователю research.md. **Не переходить к PLAN пока research не утверждён.**

Пользователь может:
- **Утвердить** — переходим к PLAN
- **Уточнить** — обновить research.md, показать снова
- **Отклонить** — пересмотреть подход

### 3. PLAN — план решения

**Артефакт:** Сохранить `docs/llm/tasks/{TASK_ID}/spec.md`:

```markdown
# {TASK_ID} — Спецификация

## Summary
{1-2 предложения что делаем}

## Шаги реализации
1. [ ] {конкретное действие — атомарное, проверяемое}
2. [ ] {следующее действие}
3. [ ] ...

Пример для задачи с изменением схемы БД (стадия Dev+):
1. [ ] Изменить схему в `docs/{name}.pgd` (/pgd)
2. [ ] `pgdesigner diff old.pgd new.pgd` → миграция в `docs/patches/`
3. [ ] `pgdesigner generate` → обновить `docs/{name}.sql` (всегда актуальный)
4. [ ] `pgmigrator run` → `make mfd-xml` → `make mfd-model` → `make mfd-repo NS={ns}`
5. [ ] Добавить бизнес-логику в `pkg/{domain}/{file}.go`
6. [ ] Добавить RPC-метод в `pkg/rpc/{file}.go` с zenrpc-аннотациями
7. [ ] `make generate`
8. [ ] Написать тесты

Пример для бага:
1. [ ] Исправить `pkg/rpc/order.go:142` — nil check перед обращением к pointer
2. [ ] Добавить тест на этот edge case
3. [ ] `make generate` (если менялись аннотации)

## Миграции (если есть SQL-изменения)
- Стадия: {Идея — нет миграций, правим sql напрямую / Dev+ — миграция через pgdesigner diff}
- [ ] Схема `docs/{name}.pgd` обновлена
- [ ] `docs/{name}.sql` обновлён (pgdesigner generate)
- [ ] Миграция в `docs/patches/` (pgdesigner diff или вручную)
- [ ] Нет блокирующих ALTER на больших таблицах
- [ ] CREATE INDEX CONCURRENTLY → `-NONTR.sql`
- План отката: {описание или "не требуется"}

## API compatibility (если меняются RPC-методы)
- [ ] Нет breaking changes для существующих клиентов
- [ ] Новые параметры опциональны или с default
- Breaking changes: {описание или "нет"}

## Примеры кода (скелеты)

Показать ключевые фрагменты кода до реализации — сигнатуры, модели, конвертеры. Пользователь проверяет архитектуру до написания кода.

```go
// Модель (если новый тип)
type Order struct {
    ID     int    `json:"id"`
    Title  string `json:"title" validate:"required,max=255"`
    UserID int    `json:"userId"`
}

// Конвертер (colgen MapP)
func NewOrder(in *db.Order) *Order { ... }
//colgen:Order:MapP(db)

// RPC-метод (сигнатура + zenrpc-аннотации)
// Create creates new order.
//
//zenrpc:order Order
//zenrpc:return Order
//zenrpc:500 Internal Error
func (s OrderService) Create(ctx context.Context, order Order) (*Order, error) {
```

Абстрактный пример — заменить на реальный код задачи.

## Pre-review checklist (чтобы не огребать на /go-review)
- [ ] Конвертеры между слоями через colgen (MapP/Map для каждого нового типа)
- [ ] `make generate` чистый (нет неожиданных diff в *_zenrpc.go, *_colgen.go)
- [ ] Authz: проверка прав внутри методов, не только middleware (IDOR)
- [ ] Errors: `NewStringError` для клиента, `newInternalError` для Sentry
- [ ] Логирование: достаточно для диагностики нового функционала
- [ ] Тесты: happy path + основные error cases

## Стиль кода
- Пиши как Dave Cheney: ясные зависимости, никакой магии, каждая функция понятна без контекста
- Пиши как Rob Pike: три строки простого кода лучше одной умной, никаких абстракций ради абстракций
- Не добавляй то, что не просили. Не рефактори соседний код. Не добавляй "на будущее"

## Критерии готовности
- [ ] Тесты проходят
- [ ] make lint чисто
- [ ] Pre-review checklist пройден
- [ ] /go-review без блокеров
- [ ] Схема и sql актуальны (если менялась БД)
- [ ] Миграция безопасна (если стадия Dev+)
- [ ] API совместимость сохранена (если менялись методы)
```

### ⏸ HITL: Утверждение spec

Показать пользователю spec.md (включая примеры кода). **Не переходить к TEST/IMPLEMENT пока spec не утверждён.**

Пользователь может:
- **Утвердить** — переходим к TEST → IMPLEMENT
- **Скорректировать** — обновить spec.md, показать снова
- **Отклонить** — вернуться к research

### 4. TEST — написать тесты (TDD)

Сначала тесты, потом реализация:
- Написать тесты для ожидаемого поведения (скилл /testing)
- Тесты должны **падать** на этом этапе — это нормально
- Использовать фабрики из `pkg/db/test/` для тестовых данных
- Покрыть happy path + основные error cases

```bash
make test  # убедиться что тесты падают по правильной причине
```

### 5. IMPLEMENT — реализация

Реализовать по утверждённой spec.md:
- Писать код пошагово, следуя плану
- Тесты из шага 4 должны **проходить** после реализации

**Правило генерации:** если изменены структуры или методы в `pkg/rpc/`, `pkg/vt/`, `pkg/intrpc/` или любом пакете с `//go:generate` — обязательно:
```bash
make generate  # zenrpc + colgen
```
Закоммитить обновлённые `*_zenrpc.go` и `*_colgen.go` вместе с изменениями. Без этого SMD/OpenRPC schema будет устаревшей.

### 6. SIMPLIFY — упрощение кода

Проверить изменённые файлы (вызвать /simplify если доступен):
- Можно ли упростить без потери читаемости
- Нет ли дублирования
- Нет ли over-engineering

### 7. FMT + LINT — форматирование и линтинг

```bash
make fmt
make lint
```

Если lint находит ошибки — исправить и вернуться к шагу 6 (SIMPLIFY).

### 8. VERIFY — сборка, тесты, совместимость

```bash
make build
make test
```

Все тесты (включая написанные в шаге 4) должны проходить. Если падают — вернуться к IMPLEMENT.

Дополнительно (если применимо по spec.md):
- **Миграции:** `pgmigrator dryrun` — проверить что миграция применяется без ошибок
- **API compatibility:** `make generate` должен быть чистый (нет неожиданных diff в `*_zenrpc.go`)
- **Dependencies:** `go mod tidy && go mod vendor` без неожиданных изменений

### 8b. API VERIFY (если менялся API-контракт)

Когда нужно: новые JSON-поля, изменённые response-структуры, новые методы.
Когда не нужно: внутренняя логика, рефакторинг без изменения API.

1. Запустить сервер: `make run &`
2. Получить auth credentials (если метод требует авторизации):
   ```bash
   psql -d {database} -c 'SELECT "{auth_key_field}" FROM "{users_table}" WHERE {condition} LIMIT 1;'
   ```
3. Вызвать затронутый метод:
   ```bash
   curl -s http://localhost:{port}/{rpc_endpoint} \
     -H "Content-Type: application/json" \
     -H "{auth_header}: {auth_value}" \
     -d '{"jsonrpc":"2.0","method":"{method}","params":{...},"id":1}'
   ```
4. Убедиться что новое поле присутствует и содержит корректные данные
5. Остановить сервер

> Auth credentials, порт, endpoint, таблица пользователей — из project-index.md и cfg/local.toml.

### 9. REVIEW — code review

Вызвать `/go-review` на свои изменения — 6 ревьюеров:
1. Common — соответствие задаче
2. Architecture (Dave Cheney) — бизнес-логика
3. Code (Rob Pike) — упрощение
4. Security (Filippo Valsorda) — безопасность
5. Tests (Mitchell Hashimoto) — тесты
6. Operability (Peter Bourgon) — операционная готовность

**Артефакт:** Сохранить результат ревью:
- Первое ревью → `docs/llm/tasks/{TASK_ID}/review-initial.md`
- После исправлений (если были) → `docs/llm/tasks/{TASK_ID}/review-final.md`

### ⏸ HITL: Оценка ревью

Показать результаты ревью пользователю. Пользователь решает:
- **Approve** — идём к коммиту
- **Fix** — вернуться к IMPLEMENT, исправить замечания (→ повторить SIMPLIFY → FMT+LINT → VERIFY → REVIEW)

### 10. COMMIT — коммит в ветку задачи

```bash
# Создать ветку (если не существует)
git checkout -b {TASK_ID}

# Финальный fmt + lint
make fmt
make lint

# Сгенерировать commit message
# /commit-msg
```

### ⏸ HITL: Подтверждение коммита

Показать:
- Ветку: `{TASK_ID}`
- Commit message
- `git diff --stat`
- Артефакты: `docs/llm/tasks/{TASK_ID}/` (research, spec, review)

Пользователь подтверждает:
- **Commit** — `git add {files} && git commit`
- **Commit + Push + MR** — одной командой:
  ```bash
  git add {files} && git commit && git push -u origin {TASK_ID} \
    -o merge_request.create \
    -o merge_request.target=devel \
    -o "merge_request.title={TASK_ID} {commit_title}"
  ```
- **Отмена** — не коммитить

> Push + MR создаются одной командой через GitLab push options. Второй push без новых коммитов не создаст MR.

### 11. YOUTRACK — обновить задачу после пуша

После успешного push в origin.

### ⏸ HITL: Подтверждение обновления YouTrack

Показать:
- Задача: `{TASK_ID}`
- Assignee: текущий → `{login}` (если не назначен)
- Stage: текущий → Review
- MR: `{mr_url}`

Пользователь подтверждает:
- **Да** — назначить и перевести
- **Только Review** — только перевести Stage
- **Нет** — оставить как есть

Выполнение (параллельно):

```bash
# Назначить на пользователя
pcurl @{yt_profile} 'https://{yt_host}/api/issues/{TASK_ID}' -s -X POST \
  -H 'Content-Type: application/json' \
  -d '{"customFields":[{"name":"Assignee","$type":"SingleUserIssueCustomField","value":{"login":"{login}"}}]}'

# Перевести в Review
pcurl @{yt_profile} 'https://{yt_host}/api/issues/{TASK_ID}' -s -X POST \
  -H 'Content-Type: application/json' \
  -d '{"customFields":[{"name":"{state_field}","$type":"StateIssueCustomField","value":{"name":"Review"}}]}'
```

> Имя поля (Stage/State/Status) и значения берутся из `project-index.md` секции YouTrack.

---

## Правила

- **Никогда не коммитить без подтверждения пользователя**
- **Никогда не пушить без явного подтверждения**
- **Любой дополнительный коммит после пуша тоже требует подтверждения** (CI упал → hotfix → ⏸ HITL)
- Ветка всегда по ID задачи: `PLF-819`, `WEB-456`
- `make fmt lint` запускается автоматически перед review и перед коммитом
- `/go-review` — всегда, без исключений
- При возврате на IMPLEMENT после ревью — повторить весь цикл SIMPLIFY → FMT+LINT → VERIFY → REVIEW
- Если задача слишком большая — предложить разбить на подзадачи
- **Все задачи из YouTrack решать ТОЛЬКО через /solve** — даже если кажутся простыми. Это гарантирует артефакты, ревью и HITL на каждом шаге
- Использовать скиллы по контексту: /mfd, /zenrpc, /colgen, /pgd при работе с соответствующим кодом
- Артефакты в `docs/llm/tasks/{TASK_ID}/` коммитятся вместе с кодом
