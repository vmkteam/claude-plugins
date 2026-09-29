# /solve — коммит, публикация, YouTrack, уроки

Шаги 10–13 из `/solve`. Правила из SKILL.md действуют и здесь: ничего не коммитить и не пушить без подтверждения.

### 10. COMMIT — коммит в ветку задачи

Проверь, что в `docs/llm/tasks/{TASK_ID}/` есть `research.md`, `spec.md` и `review-*.md` — они понадобятся для публикации. Если какого-то файла нет — скажи пользователю, какого и почему, не восстанавливай задним числом.

fmt, lint и тесты уже прошли на VERIFY после последней правки кода. Если код менялся позже — повтори шаги 7–8.

Ветка: `git switch -c {TASK_ID}`, если её ещё нет. Сообщение — через /commit-msg. В коммит идёт только код, включая сгенерированные файлы; `docs/llm/tasks/` не добавляй.

### ⏸ HITL: коммит

Покажи ветку, commit message, `git diff --stat` (без `docs/llm/tasks/`) и список локальных артефактов, которые будут опубликованы после push.
- **Commit** — `git add {files} && git commit`
- **Commit + Push + MR**:
  ```bash
  git add {files}
  git commit -F - <<'MSG'
  {commit_message}
  MSG
  git push -u origin {TASK_ID} \
    -o merge_request.create \
    -o merge_request.target={base_branch} \
    -o "merge_request.title={TASK_ID} {commit_title}" \
    -o merge_request.squash_on_merge \
    -o merge_request.remove_source_branch
  ```
- **Отмена**

MR создаётся через GitLab push options только при push новых коммитов: повторный push без коммитов MR не создаст.

### 11. PUBLISH — артефакты комментарием

После успешного push. Цель — `artifacts_target` из project-index:
- `gitlab` — комментарий в MR;
- `youtrack` — комментарий в задаче;
- `ask` или не задано — ⏸ HITL: **GitLab** / **YouTrack** / **Пропустить**.

Публикуются `research.md` и `spec.md`, каждый под спойлером; `review-*.md` остаются локально. Скрипт `publish-artifacts.sh` лежит в директории этого скилла (рядом с этим файлом); запускай из корня проекта:

```bash
bash {skill_dir}/publish-artifacts.sh gitlab   @{gl_profile} {gl_host} {gl_project_id} {TASK_ID}
bash {skill_dir}/publish-artifacts.sh youtrack @{yt_profile} {yt_host} {TASK_ID}
```

Скрипт собирает JSON через jq, для GitLab находит открытый MR по ветке `{TASK_ID}` и печатает ID созданного комментария. При ошибке он печатает ответ API — покажи его пользователю.

### 12. YOUTRACK — ⏸ обновление задачи

Покажи задачу, assignee (текущий → `{login}`, если не назначен), состояние (`{state_field}`: текущее → Review) и ссылку на MR.
- **Да** — назначить и перевести в Review
- **Только Review** — только сменить состояние
- **Нет** — оставить как есть

```bash
# Назначить
pcurl @{yt_profile} 'https://{yt_host}/api/issues/{TASK_ID}' -s -X POST \
  -H 'Content-Type: application/json' \
  -d '{"customFields":[{"name":"Assignee","$type":"SingleUserIssueCustomField","value":{"login":"{login}"}}]}'

# Перевести в Review
pcurl @{yt_profile} 'https://{yt_host}/api/issues/{TASK_ID}' -s -X POST \
  -H 'Content-Type: application/json' \
  -d '{"customFields":[{"name":"{state_field}","$type":"StateIssueCustomField","value":{"name":"Review"}}]}'
```

Имя поля состояния (Stage/State/Status) и его значения — из секции YouTrack в project-index.

### 13. LESSONS — уроки в project-index

Если по ходу задачи были провальные раунды — падал lint или тесты на шагах 7–8, ревью вернуло задачу на Fix, пришлось переделывать spec, — извлеки из них уроки для будущих задач этого проекта: что пошло не так и как этого избежать. Не было провалов — шаг пропускается.

Допиши уроки в секцию `## Уроки` файла `project-index.md` (auto-memory проекта; секции нет — создай её в конце файла), по одной строке:

```markdown
- {что пошло не так} → {как избежать} ({TASK_ID})
```

Записывай только то, что пригодится в других задачах этого репозитория, а не детали текущей. Похожий урок уже есть — уточни его, а не добавляй дубль; устаревшие удаляй. Секция должна оставаться короткой, чтобы её читали целиком в начале каждой задачи. Покажи пользователю, что добавил.
