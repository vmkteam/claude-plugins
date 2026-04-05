---
name: mr-review
description: "MR Review — ревью чужого Merge Request. Fetch diff из GitLab → /go-review → публикация замечаний как threads в MR."
---

# MR Review — ревью чужого Merge Request

Полный цикл code review для MR в GitLab: получить diff, проанализировать код, опубликовать замечания как inline threads.

Подключения из `.claude/memory/project-index.md` и `~/.claude/memory/infra-{group}.md`.

## Использование

```
/mr-review 42
/mr-review 42 --focus security
/mr-review 42 --focus performance
```

## Flow

```
FETCH MR → READ CODE → REVIEW → SUMMARY → ⏸ HITL → PUBLISH
```

---

### 1. FETCH — получить MR

```bash
# Детали MR (title, description, author, source/target branch, diff_refs)
pcurl @{gl_profile} 'https://{gl_host}/api/v4/projects/{gl_project_id}/merge_requests/{mr_iid}' -s

# Diff (список изменённых файлов с содержимым)
pcurl @{gl_profile} 'https://{gl_host}/api/v4/projects/{gl_project_id}/merge_requests/{mr_iid}/changes' -s

# Коммиты MR
pcurl @{gl_profile} 'https://{gl_host}/api/v4/projects/{gl_project_id}/merge_requests/{mr_iid}/commits' -s

# Существующие discussions (чтобы не дублировать замечания)
pcurl @{gl_profile} 'https://{gl_host}/api/v4/projects/{gl_project_id}/merge_requests/{mr_iid}/discussions?per_page=100' -s
```

Извлечь:
- `diff_refs` (base_sha, start_sha, head_sha) — нужны для inline comments
- Список изменённых файлов и их diff
- Описание MR и связанную задачу (из title или description)
- Уже существующие замечания (не дублировать)

### 2. READ CODE — прочитать контекст

Для каждого изменённого файла:
- Прочитать **полный файл** локально (не только diff) — для понимания контекста
- Если ветка MR доступна локально — `git fetch origin && git checkout {source_branch}`
- Если нет — читать через API или анализировать diff as-is

Дополнительно:
- Прочитать связанную задачу из YouTrack (если ID в title/description)
- Понять **что должен делать MR** — сравнить intent с реализацией

### 3. REVIEW — анализ кода

Запустить `/go-review` на изменения MR — 6 ревьюеров:
1. **Common** — соответствие задаче, полнота
2. **Architecture** (Dave Cheney) — структура, зависимости
3. **Code** (Rob Pike) — простота, читаемость
4. **Security** (Filippo Valsorda) — уязвимости, authz
5. **Tests** (Mitchell Hashimoto) — покрытие, качество тестов
6. **Operability** (Peter Bourgon) — логирование, метрики, graceful degradation

Если указан `--focus` — дать повышенный приоритет этому аспекту.

Дополнительные проверки (сверх /go-review):
- **Сгенерированные файлы** (`*_zenrpc.go`, `*_colgen.go`, `*_mfd.go`) — пропустить, но убедиться что они обновлены
- **Миграции** — проверить на блокирующие ALTER, наличие отката
- **`make generate` consistency** — если менялись структуры/аннотации, обновлены ли сгенерированные файлы?

### 4. SUMMARY — подготовить результат

Сформировать два артефакта:

#### a) Summary comment (общий комментарий к MR)

```markdown
## Code Review Summary

**MR:** !{mr_iid} — {title}
**Reviewed by:** Claude (/go-review — 6 perspectives)

### Verdict: {Approve / Request Changes / Comment}

### Findings
| # | Severity | File | Line | Issue |
|---|----------|------|------|-------|
| 1 | blocker | {file} | {line} | {description} |
| 2 | major | {file} | {line} | {description} |
| 3 | minor | {file} | {line} | {description} |

### What's good
- {positive finding 1}
- {positive finding 2}

### Recommendations
- {recommendation 1}
```

#### b) Inline comments (привязанные к строкам кода)

Для каждого замечания severity blocker/major/minor — подготовить inline comment с:
- Severity tag: `**[blocker]**`, `**[major]**`, `**[minor]**`
- Описание проблемы
- Предложение исправления (с примером кода если уместно)

Замечания `nit` — включить только в summary, не создавать отдельные threads.

### ⏸ HITL: Утверждение ревью

Показать пользователю:
- Summary comment
- Список inline comments с файлами и строками
- Рекомендованный verdict (Approve / Request Changes / Comment)

Пользователь решает:
- **Publish all** — опубликовать summary + все inline threads
- **Publish selected** — выбрать какие замечания публиковать
- **Edit** — скорректировать текст замечаний
- **Cancel** — не публиковать

### 5. PUBLISH — опубликовать в GitLab

#### Summary comment:
```bash
pcurl @{gl_profile} 'https://{gl_host}/api/v4/projects/{gl_project_id}/merge_requests/{mr_iid}/notes' -s -X POST \
  -H 'Content-Type: application/json' \
  -d '{"body": "{summary_markdown}"}'
```

#### Inline threads (для каждого замечания):
```bash
pcurl @{gl_profile} 'https://{gl_host}/api/v4/projects/{gl_project_id}/merge_requests/{mr_iid}/discussions' -s -X POST \
  -H 'Content-Type: application/json' \
  -d '{
    "body": "{comment_text}",
    "position": {
      "base_sha": "{base_sha}",
      "start_sha": "{start_sha}",
      "head_sha": "{head_sha}",
      "position_type": "text",
      "old_path": "{file_path}",
      "new_path": "{file_path}",
      "new_line": {line_number}
    }
  }'
```

> `base_sha`, `start_sha`, `head_sha` из `diff_refs` (шаг 1).
> `new_line` — номер строки в новой версии файла.
> Для удалённых строк использовать `old_line` вместо `new_line`.

#### Approve (если verdict = Approve):
```bash
pcurl @{gl_profile} 'https://{gl_host}/api/v4/projects/{gl_project_id}/merge_requests/{mr_iid}/approve' -s -X POST
```

---

## Правила

- **Никогда не публиковать без подтверждения пользователя**
- Не дублировать замечания, которые уже есть в discussions
- Пропускать сгенерированные файлы (но проверять их актуальность)
- Быть конструктивным: предлагать решение, а не только указывать проблему
- Severity blocker — только для реальных багов, уязвимостей, потери данных
- Если MR слишком большой (>1000 строк diff) — предупредить и предложить ревью по частям
