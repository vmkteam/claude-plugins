---
name: solve
description: "Solve — полный цикл решения задачи из YouTrack: preflight → анализ → план → реализация → ревью → коммит. Используй при любой YouTrack-задаче (`/solve PLF-819`); флаг `--fast` сокращает HITL для тривиальных багфиксов."
---

# /solve — решение задачи

Полный цикл решения задачи из YouTrack с human-in-the-loop на ключевых этапах.
Подключения к системам из `.claude/memory/project-index.md`.

## Использование

```
/solve PLF-819                 # полный цикл с 5 HITL
/solve PLF-819 --fast          # ускоренный режим: 2 HITL (commit + youtrack)
/solve --fast WEB-456          # позиция флага любая
```

### Флаг `--fast`

Для тривиальных багфиксов и повторяющихся паттернов. Пропускает HITL-паузы **research** и **spec** — шаги выполняются и артефакты пишутся, но пользователя не спрашивают до COMMIT.

**Что делает `--fast`:**
- ANALYZE и PLAN объединяются в одну plan-mode сессию (research.md + spec.md создаются подряд, один exit из plan mode вместо двух)
- REVIEW (/go-review) выполняется, показывается пользователю, но без отдельного HITL до коммита
- PREFLIGHT, COMMIT HITL, YOUTRACK HITL — остаются обязательными

**Когда НЕ использовать:**
- Сложная архитектурная задача
- Новый сервис/модуль
- Задача затрагивает больше 3 файлов
- Есть сомнения в требованиях

Если пользователь запускает `/solve --fast`, а задача крупная — предложи переключиться на обычный режим перед PLAN.

## Артефакты

Каждый этап создаёт документ в `docs/llm/tasks/{TASK_ID}/`:

```
docs/llm/tasks/PLF-819/
├── research.md          — анализ задачи, контекст, вопросы (шаг 2)
├── spec.md              — спецификация плана реализации (шаг 3)
├── review-initial.md    — первое ревью (шаг 9)
└── review-final.md      — финальное ревью перед коммитом (шаг 9, повторное)
```

## Flow

```
PREFLIGHT → FETCH → ANALYZE → research.md → ⏸
  → PLAN → spec.md → ⏸
  → TEST → IMPLEMENT → SIMPLIFY → FMT+LINT → VERIFY
  → REVIEW → ⏸
  → COMMIT → ⏸
  → YOUTRACK → ⏸
```

**Важно:**
- PLAN начинается только после утверждения research
- IMPLEMENT — только после утверждения spec
- REVIEW (/go-review) — всегда, без исключений

---

### 0. PREFLIGHT — актуальность базовой ветки

Перед любым workflow проверить, что локальный базовый бранч синхронизирован с `origin`. Иначе analyze/plan/review пойдут по устаревшему коду.

Имя базовой ветки — из `project-index.md` (`base_branch`, по умолчанию `devel`).

```bash
BASE={base_branch}
git fetch origin $BASE --quiet
LOCAL=$(git rev-parse $BASE 2>/dev/null || echo none)
REMOTE=$(git rev-parse origin/$BASE)
BEHIND=$(git rev-list --count $BASE..origin/$BASE 2>/dev/null || echo ?)
```

Если `LOCAL != REMOTE` (локальный отстаёт/расходится) — ⏸ HITL:
- **Обновить** — `git checkout $BASE && git pull --ff-only` (при незакоммиченных изменениях сначала stash), затем вернуться на исходную ветку
- **Продолжить** — на свой риск, база устаревшая (явно предупредить пользователя)
- **Отмена** — прервать workflow

Если `LOCAL == REMOTE` — переходить к FETCH без вопросов.

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

Проверить `.gitignore` на наличие `docs/llm/`. Если нет — предложить пользователю добавить (артефакты никогда не коммитятся).

**Аттачи:**
```bash
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
pcurl @{sentry_profile} 'https://{sentry_host}/api/0/organizations/{org}/issues/?query=is:unresolved+{keywords}&sort=freq&statsPeriod=7d&limit=5' -s
```

Полный (вызвать /investigate):
- Sentry — ошибки и stacktrace
- Prometheus — error rate, latency аномалии за период
- Loki — логи с ошибками по методу/endpoint
- API — воспроизвести запрос на dev, проверить на prod
- Сравнить задеплоенную версию с кодом (Sentry release commit)

**Артефакт:** Прочитать шаблон из `skills/solve/research-template.md`, заполнить и сохранить как `docs/llm/tasks/{TASK_ID}/research.md`.

### ⏸ HITL: Утверждение research _(пропускается в `--fast`)_

**Чеклист артефактов:** убедиться что `docs/llm/tasks/{TASK_ID}/research.md` записан на диск.

В обычном режиме показать пользователю research.md. **Не переходить к PLAN пока research не утверждён.** Пользователь может:
- **Утвердить** — переходим к PLAN
- **Уточнить** — обновить research.md, показать снова
- **Отклонить** — пересмотреть подход

В `--fast` пауза пропускается — сразу переходим к PLAN в той же plan-mode сессии.

### 3. PLAN — план решения (plan mode)

Оставаться в plan mode. Продумать:
- Какие слои затронуты (db → domain → rpc) и в каком порядке менять
- Поток данных: откуда приходит, как трансформируется, куда уходит
- Какие существующие паттерны в проекте переиспользовать (найти аналоги через grep)
- Нужны ли изменения схемы БД → /pgd или /pgmdd
- Нужны ли поиски/фильтрация → /mfd SearchObject
- Нужны ли новые конвертеры → /colgen
- Есть ли зависимости между шагами (миграция до модели, модель до RPC)

Написать **реальные скелеты кода** из текущей задачи — сигнатуры функций, структуры, конвертеры. Не абстрактные примеры.

**СОХРАНИТЬ:** прочитать шаблон из `skills/solve/spec-template.md`, заполнить и записать как `docs/llm/tasks/{TASK_ID}/spec.md` через Write tool. Не откладывать.
Секции "Миграции" и "API compatibility" включать только если применимо к задаче.

### ⏸ HITL: Утверждение spec _(в `--fast` — единая точка выхода из plan mode для research+spec)_

**Чеклист артефактов:** убедиться что `docs/llm/tasks/{TASK_ID}/spec.md` записан на диск.

**Обычный режим:** показать пользователю spec.md (включая примеры кода). Не переходить к TEST/IMPLEMENT пока spec не утверждён. Пользователь может:
- **Утвердить** — переходим к TEST → IMPLEMENT
- **Скорректировать** — обновить spec.md, показать снова
- **Отклонить** — вернуться к research

**`--fast` режим:** research.md и spec.md показываются подряд одним блоком, пользователь подтверждает оба одним действием (выход из plan mode). Если задача оказалась крупнее ожидаемого — предложить переключиться в обычный режим и прервать поток.

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

**Работа с БД:** при изменениях схемы, моделей или поисков использовать скиллы /pgd (или /pgmdd) и /mfd. Стандартные поиски и фильтрация всегда добавляются через /mfd (SearchObject).

**Правило генерации:** если изменены структуры или методы в `pkg/rpc/`, `pkg/vt/`, `pkg/intrpc/` или любом пакете с `//go:generate` — обязательно:
```bash
make generate  # zenrpc + colgen
```
Закоммитить обновлённые `*_zenrpc.go` и `*_colgen.go` вместе с изменениями. Без этого SMD/OpenRPC schema будет устаревшей.

**Актуализация артефактов:** после реализации, пока контекст свежий — обновить артефакты:
- Если реализация отклонилась от spec.md (изменился план, добавились/убрались шаги, поменялись сигнатуры) — обновить spec.md, отметив выполненные шаги `[x]` и добавив фактические отличия.
- Если изменилось понимание задачи, scope или root cause — обновить research.md.

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

**Перечитать этот SKILL.md через Read tool** если прошло много шагов — контекст мог быть сжат.

Вызвать `/go-review` на свои изменения — 6 ревьюеров:
1. Common — соответствие задаче
2. Architecture (Dave Cheney) — бизнес-логика
3. Code (Rob Pike) — упрощение
4. Security (Filippo Valsorda) — безопасность
5. Tests (Mitchell Hashimoto) — тесты
6. Operability (Peter Bourgon) — операционная готовность

**СРАЗУ после получения результатов ревью** сохранить в файл через Write tool:
- Первое ревью → `docs/llm/tasks/{TASK_ID}/review-initial.md`
- После исправлений → `docs/llm/tasks/{TASK_ID}/review-final.md`

### ⏸ HITL: Оценка ревью _(пропускается в `--fast` если нет blocker/major)_

**Чеклист артефактов:** убедиться что `docs/llm/tasks/{TASK_ID}/review-initial.md` (или `review-final.md`) записан на диск.

Показать результаты ревью пользователю. Пользователь решает:
- **Approve** — идём к коммиту
- **Fix** — вернуться к IMPLEMENT, исправить замечания (→ повторить SIMPLIFY → FMT+LINT → VERIFY → REVIEW)

**`--fast` режим:** если в ревью нет `blocker`/`major` замечаний — автоматически идти к HITL коммита (замечания `minor`/`nit` показать пользователю там же). Если есть `blocker`/`major` — пауза включается вне зависимости от флага.

### Pre-commit checklist — артефакты

**Перечитать этот SKILL.md через Read tool** если контекст мог быть сжат.

Проверить что ВСЕ артефакты существуют на диске:
- [ ] `docs/llm/tasks/{TASK_ID}/research.md`
- [ ] `docs/llm/tasks/{TASK_ID}/spec.md`
- [ ] `docs/llm/tasks/{TASK_ID}/review-initial.md` (или `review-final.md`)

Если файл отсутствует — создать его СЕЙЧАС через Write tool, восстановив содержимое из контекста.

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

**Артефакты:** `docs/llm/tasks/` **НЕ коммитится никогда** — остаётся локально. Публикуется как коммент (шаг 11b) в GitLab или YouTrack по настройке `artifacts_target` из `project-index.md`. Убедись, что `docs/llm/` в `.gitignore` — если нет, предложи добавить.

### ⏸ HITL: Подтверждение коммита

Показать:
- Ветку: `{TASK_ID}`
- Commit message
- `git diff --stat` (без `docs/llm/` — артефакты не коммитятся)
- Локальные артефакты: `docs/llm/tasks/{TASK_ID}/` (research, spec, review) — будут опубликованы комментом на шаге 11b

Пользователь подтверждает:
- **Commit** — `git add {files} && git commit`
- **Commit + Push + MR** — одной командой:
  ```bash
  git add {files} && git commit && git push -u origin {TASK_ID} \
    -o merge_request.create \
    -o merge_request.target=devel \
    -o "merge_request.title={TASK_ID} {commit_title}" \
    -o merge_request.squash_on_merge \
    -o merge_request.remove_source_branch
  ```
- **Отмена** — не коммитить

> Push + MR создаются одной командой через GitLab push options. Второй push без новых коммитов не создаст MR.

### 11. YOUTRACK — обновить задачу после пуша

После успешного push в origin.

### 11b. ARTIFACTS — публикация артефактов комментом

Проверить `artifacts_target` в `project-index.md`:
- `gitlab` → сразу публиковать в MR (вариант A)
- `youtrack` → сразу публиковать в задачу (вариант B)
- `ask` или не задано → спросить пользователя

### ⏸ HITL: Куда прикрепить артефакты? (только при `ask`)

- **GitLab** — коммент в Merge Request
- **YouTrack** — коммент в задаче
- **Пропустить** — не публиковать

#### Вариант A: Коммент в MR (GitLab)

Один коммент с двумя спойлерами (research + spec). Review не публикуется — это внутренний артефакт.

```bash
# Получить MR IID по ветке
MR_IID=$(pcurl @{gl_profile} 'https://{gl_host}/api/v4/projects/{gl_project_id}/merge_requests?source_branch={TASK_ID}&state=opened' -s | jq -r '.[0].iid')

# Собрать коммент из файлов
RESEARCH=$(cat docs/llm/tasks/{TASK_ID}/research.md)
SPEC=$(cat docs/llm/tasks/{TASK_ID}/spec.md)

# Создать коммент со спойлерами
pcurl @{gl_profile} 'https://{gl_host}/api/v4/projects/{gl_project_id}/merge_requests/'"${MR_IID}"'/notes' -s \
  -X POST --data-urlencode "body=## Артефакты /solve

<details>
<summary>Research — анализ задачи</summary>

${RESEARCH}

</details>

<details>
<summary>Spec — план реализации</summary>

${SPEC}

</details>"
```

#### Вариант B: Коммент в YouTrack

Один коммент с двумя спойлерами (YouTrack `{cut}` синтаксис).

```bash
RESEARCH=$(cat docs/llm/tasks/{TASK_ID}/research.md)
SPEC=$(cat docs/llm/tasks/{TASK_ID}/spec.md)

pcurl @{yt_profile} 'https://{yt_host}/api/issues/{TASK_ID}/comments?fields=id,text' -s \
  -X POST -H 'Content-Type: application/json' \
  -d '{
    "text": "**Артефакты /solve**\n\n{cut text=\"Research — анализ задачи\"}\n'"$(echo "$RESEARCH" | jq -sR .)"'\n{cut}\n\n{cut text=\"Spec — план реализации\"}\n'"$(echo "$SPEC" | jq -sR .)"'\n{cut}"
  }'
```

> В обоих вариантах review-артефакты (review-initial.md, review-final.md) не публикуются — они нужны только в процессе работы.
> `docs/llm/tasks/{TASK_ID}/` всегда остаётся только локально — в коммит никогда не попадает.

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
- `/go-review` — всегда, без исключений (даже в `--fast`)
- `--fast` не пропускает PREFLIGHT, VERIFY, REVIEW, COMMIT HITL, YOUTRACK HITL. Пропускает только паузы research и spec (объединяет их в одну) и review HITL при отсутствии blocker/major
- При возврате на IMPLEMENT после ревью — повторить весь цикл SIMPLIFY → FMT+LINT → VERIFY → REVIEW
- Если задача слишком большая — предложить разбить на подзадачи
- **Все задачи из YouTrack решать ТОЛЬКО через /solve** — даже если кажутся простыми. Это гарантирует артефакты, ревью и HITL на каждом шаге
- Использовать скиллы по контексту: /mfd, /zenrpc, /colgen, /pgd при работе с соответствующим кодом
- Артефакты в `docs/llm/tasks/{TASK_ID}/` **никогда не коммитятся** — публикуются как коммент со спойлерами в GitLab MR или YouTrack. Цель настраивается через `artifacts_target` в `project-index.md` (`gitlab` / `youtrack` / `ask`). `docs/llm/` должен быть в `.gitignore`
