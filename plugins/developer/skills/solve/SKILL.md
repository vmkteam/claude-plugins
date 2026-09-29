---
name: solve
description: "Solve — полный цикл решения задачи из YouTrack: preflight → анализ → план → реализация → ревью → коммит. Используй при любой YouTrack-задаче (`/solve PLF-819`); флаг `--fast` сокращает HITL для тривиальных багфиксов."
argument-hint: "<TASK_ID> [--fast]"
---

# /solve — решение задачи

Полный цикл решения задачи из YouTrack с подтверждением пользователя (HITL) на ключевых этапах. Подключения к системам — из `project-index.md` в auto-memory проекта и связанного с ним `~/.claude/memory/infra-{group}.md` (их создаёт `/onboard`).

## Правила

- Не коммитить и не пушить без явного подтверждения пользователя. Дополнительный коммит после пуша (упал CI, hotfix) — тоже через HITL.
- Код не менять до утверждения spec.
- `/go-review` — всегда, в том числе в `--fast`.
- Ветка — по ID задачи: `PLF-819`, `WEB-456`.
- `docs/llm/tasks/` не коммитится: артефакты остаются локально и публикуются комментарием. `docs/llm/tasks/` должен быть в `.gitignore` (остальной `docs/llm/` в некоторых проектах — закоммиченная документация).
- ⏸ HITL — вопрос пользователю через AskUserQuestion с перечисленными вариантами, а для research и spec — выход из plan mode через ExitPlanMode. Следующий шаг — только после ответа.
- Если задача оказалась слишком большой — предложить `/decompose`.
- Если после сжатия контекста описание шагов видно не полностью — перечитай `${CLAUDE_SKILL_DIR}/SKILL.md`, прежде чем продолжать.
- По ходу работы подключай скиллы по контексту: /mfd, /zenrpc, /colgen, /pgd или /pgmdd, /testing.

## Использование

```
/solve PLF-819            # полный цикл, 5 HITL
/solve PLF-819 --fast     # 2 HITL: коммит и YouTrack
```

Флаг может стоять в любой позиции.

### `--fast`

Для тривиальных багфиксов и повторяющихся паттернов. ANALYZE и PLAN проходят в одной сессии plan mode: файл плана содержит research и spec, и один выход из plan mode утверждает оба. HITL ревью пропускается, если в ревью нет blocker/major — тогда minor/nit показываются в HITL коммита. PREFLIGHT, VERIFY, REVIEW, HITL коммита и HITL YouTrack остаются.

Не подходит для архитектурных задач, нового сервиса или модуля, изменений больше чем в 3 файлах и неясных требований. Если задача с `--fast` оказалась крупной — предложи обычный режим до PLAN.

## Артефакты

В `docs/llm/tasks/{TASK_ID}/`: `research.md` (шаг 2), `spec.md` (шаг 3), `review-initial.md` и `review-final.md` (шаг 9). Шаблоны: `${CLAUDE_SKILL_DIR}/research-template.md` и `${CLAUDE_SKILL_DIR}/spec-template.md`. Секции, которые к задаче не относятся, не включай; объём артефакта — по сложности задачи.

## Flow

```
PREFLIGHT → FETCH → ANALYZE (plan mode) → ⏸ research
  → PLAN (plan mode) → ⏸ spec
  → TEST → IMPLEMENT → SIMPLIFY → FMT+LINT → VERIFY
  → REVIEW → ⏸
  → COMMIT → ⏸
  → PUBLISH → YOUTRACK → ⏸ → LESSONS
```

Шаги 10–13 (COMMIT и дальше) описаны в `${CLAUDE_SKILL_DIR}/commit.md`.

---

### 0. PREFLIGHT — актуальность базовой ветки

База — `base_branch` из project-index (по умолчанию `devel`). На устаревшей базе анализ и ревью идут по старому коду.

```bash
git fetch origin {base_branch} --quiet && git rev-list --left-right --count {base_branch}...origin/{base_branch}
```

Вывод `0	0` — база актуальна, переходи к FETCH. Иначе — ⏸ HITL:
- **Обновить** — на базовой ветке: `git pull --ff-only`; на другой ветке: `git fetch origin {base_branch}:{base_branch}`
- **Продолжить** — на устаревшей базе, явно предупредив пользователя
- **Отмена**

Если локальной базовой ветки нет — сравнивать не с чем, продолжай.

### 1. FETCH — задача и аттачи

```bash
pcurl @{yt_profile} 'https://{yt_host}/api/issues/{TASK_ID}?fields=idReadable,summary,description,created,updated,reporter(login,name),assignee(login,name),tags(name),comments(author(login),text,created),customFields(name,value(name)),links(direction,linkType(name),issues(idReadable,summary,resolved))' -s
pcurl @{yt_profile} 'https://{yt_host}/api/issues/{TASK_ID}/attachments?fields=id,name,url,mimeType,size' -s
```

Читай и комментарии — в них бывают уточнения.

`mkdir -p docs/llm/tasks/{TASK_ID}`. Если `docs/llm/tasks/` не игнорируется (`git check-ignore -q docs/llm/tasks/x`) — предложи добавить `docs/llm/tasks/` в `.gitignore`. Аттачи `image/*` и `application/pdf` скачай туда же и прочитай: `pcurl @{yt_profile} 'https://{yt_host}{url}' -s -o docs/llm/tasks/{TASK_ID}/{name}`. Остальные форматы — только упомянуть в research.

FETCH идёт до plan mode, потому что в plan mode файлы писать нельзя.

### 2. ANALYZE — исследование (plan mode)

Войди в plan mode (EnterPlanMode): правки файлов в нём заблокированы, читать код и выполнять запросы можно.

Собери контекст:
- секция «Уроки» в project-index — грабли прошлых задач этого проекта; учти их в плане;
- связанные задачи из FETCH — прочитай те, что влияют на понимание;
- git-история: `git log --oneline --all --grep="{TASK_ID}"` (и по parent), `git log --oneline -10 -- {file}` по затронутым файлам;
- код: затронутые пакеты и файлы, существующие тесты, для фичи — scope изменений.

Для бага найди root cause. Ясная ошибка или stacktrace в описании — Sentry по ключевым словам, git log и код:

```bash
pcurl @{sentry_profile} 'https://{sentry_host}/api/0/organizations/{org}/issues/?query=is:unresolved+{keywords}&sort=freq&statsPeriod=7d&limit=5' -s
```

Причина непонятна, «иногда не работает», деградация — вызови `/investigate`: Sentry, Prometheus, Loki, проверка API на dev/prod, сравнение задеплоенной версии с кодом. В plan mode он вернёт отчёт текстом: выводы — в Root Cause research, а сам отчёт сохрани после утверждения research.

Research по шаблону `${CLAUDE_SKILL_DIR}/research-template.md` запиши в файл плана, который указал plan mode.

### ⏸ HITL: research _(в `--fast` пропускается)_

ExitPlanMode показывает research пользователю — это и есть утверждение.
- **Утвердил** — сохрани тот же текст в `docs/llm/tasks/{TASK_ID}/research.md` (и отчёт /investigate, если он был, — в `investigation.md` рядом) и переходи к PLAN.
- **Отклонил с замечаниями** — останься в plan mode, обнови research и снова вызови ExitPlanMode.

В `--fast` из plan mode не выходи: переходи к PLAN и допиши spec в тот же файл плана.

### 3. PLAN — spec (plan mode)

Снова войди в plan mode (в `--fast` — продолжай текущую сессию). Продумай:
- какие слои затронуты (db → domain → rpc) и в каком порядке их менять; поток данных;
- какие паттерны проекта переиспользовать — найди аналоги в коде;
- схема БД → /pgd или /pgmdd; поиски и фильтры → /mfd (SearchObject); конвертеры → /colgen;
- зависимости между шагами: миграция до модели, модель до RPC.

Spec по шаблону `${CLAUDE_SKILL_DIR}/spec-template.md` — с реальными скелетами кода этой задачи (сигнатуры, структуры, конвертеры, RPC-методы). Если задача меняет поведение — добавь границы (что не делаем) и сценарии Given/When/Then с конкретными данными: happy path, альтернативные ветки, ошибки, граничные значения, конкурентный доступ, если он возможен; похожие сводятся в Scenario Outline. Затем перепроверь сценарии: на каждый edge case и каждый переход статуса есть сценарий, данные конкретные, а Then проверяем тестом («тесты зелёные» — не результат). Дыры закрой в spec и сценариях и перепроверь добавленное. Итог — в секцию «Самопроверка сценариев», её пользователь видит при утверждении spec. Запиши в файл плана.

### ⏸ HITL: spec

ExitPlanMode — утверждение spec (в `--fast` — research и spec вместе).
- **Утвердил** — сохрани `docs/llm/tasks/{TASK_ID}/spec.md` (в `--fast` — ещё `research.md` и `investigation.md`, если был /investigate) и переходи к TEST.
- **Отклонил с замечаниями** — обнови spec в plan mode и снова вызови ExitPlanMode. Если замечания ставят под сомнение research — вернись к нему.

### 4. TEST — тесты до реализации

Тесты на ожидаемое поведение по /testing — из сценариев spec: happy path и основные error cases, фабрики из `pkg/db/test/`. Если в задаче есть числовой или глобальный инвариант («≤ N», «суммарно», «не превышает лимит», «во всех ветках») — начни с теста на худший случай (максимум полей, длины, количества): инвариант без такого теста считается невыполненным. `make test` — новые тесты должны падать, причём по правильной причине.

### 5. IMPLEMENT — реализация по spec

Пиши код по шагам spec; тесты из шага 4 должны пройти. Конвенции vmkteam:
- делай ровно то, что в spec, без попутного рефакторинга соседнего кода и заделов «на будущее»; если по ходу выяснилось, что spec неверна, — скажи об этом, а не меняй scope молча;
- схема, модели, поиски — через /pgd (/pgmdd) и /mfd; стандартные поиски и фильтры — через mfd SearchObject;
- конвертеры между слоями — через colgen (Map/MapP);
- авторизация — проверка прав внутри метода, а не только в middleware (IDOR);
- ошибки: клиентские (4xx) — `zenrpc.NewStringError`, внутренние — `newInternalError(err)`: `zm.WithErrorSLog` отправит причину в Sentry, а клиенту вернёт «Internal error»;
- логирования достаточно, чтобы диагностировать новый функционал;
- новое поле или фича проходит все слои: схема → mfd → `pkg/db` → `pkg/vt` (DTO, `ToDB()`, `NewX()`) → TS-клиент → UI (форма и список/поиск, где нужно).

Изменил структуры или методы в `pkg/rpc/`, `pkg/vt/`, `pkg/intrpc/` или в пакете с `//go:generate` — запусти `make generate` (zenrpc + colgen); вся затронутая генерёнка, включая TS-клиент, перегенерирована и идёт в тот же коммит.

Если реализация разошлась с spec (другие шаги, сигнатуры) — обнови spec.md: отметь выполненные шаги `[x]` и допиши фактические отличия. Изменилось понимание задачи или root cause — обнови research.md.

### 6. SIMPLIFY

Пройди свой дифф сам, одним проходом: переиспользование (нет ли дублей и готовых функций, в том числе методов colgen), упрощение (лишние обёртки и абстракции), эффективность (аллокации и вызовы в циклах), уровень абстракции (явность там, где нужна). Меняй только то, что реально улучшает код. Полный `/simplify` запускает несколько агентов и стоит дорого — вызывай его только для крупного диффа (порядка десятка файлов и больше) или по просьбе пользователя.

### 7. FMT + LINT

`make fmt && make lint`. Ошибки lint — исправить и вернуться к SIMPLIFY.

### 8. VERIFY

`make build && make test` — проходят все тесты, включая написанные на шаге 4. Падают — вернуться к IMPLEMENT.

По spec, если применимо: миграции — `pgmigrator dryrun`; API — `make generate` без неожиданных изменений в `*_zenrpc.go`; зависимости — `go mod tidy && go mod vendor` без неожиданных изменений. Если менялся API-контракт (новые поля, методы, структуры ответов) — проверь его на локальном сервере по `${CLAUDE_SKILL_DIR}/api-verify.md`.

### 9. REVIEW

`/go-review` по изменениям, результат — в `docs/llm/tasks/{TASK_ID}/review-initial.md`. После исправлений — повторный `/go-review` по исправленным местам и изменениям после первого ревью, со сверкой с review-initial; результат — в `review-final.md`.

### ⏸ HITL: ревью _(в `--fast` — только при blocker/major)_

Покажи итог ревью.
- **Approve** — к коммиту
- **Fix** — исправить замечания, затем SIMPLIFY → FMT+LINT → VERIFY → REVIEW

Если то же замечание вернулось повторно — найди нарушенный инвариант и восстанови его во всех ветках и крайних случаях, закрыв тестом на худший случай, а не подгоняй код под пример из ревью.

### 10–13. COMMIT, PUBLISH, YOUTRACK, LESSONS

Прочитай `${CLAUDE_SKILL_DIR}/commit.md` и выполни его: коммит в ветку задачи (⏸), push и MR, публикация артефактов скриптом `${CLAUDE_SKILL_DIR}/publish-artifacts.sh`, обновление задачи в YouTrack (⏸), запись уроков в project-index.
