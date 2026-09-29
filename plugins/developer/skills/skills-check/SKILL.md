---
name: skills-check
description: "Skills Check — smoke-тесты интеграций из project-index.md. Используй для проверки что pcurl-профили и URL всех data-source скиллов ещё живы."
argument-hint: "[skill...] [--verbose]"
disable-model-invocation: true
context: fork
background: false
effort: low
allowed-tools:
  - "Bash(pcurl:*)"
  - "Bash(bash ${CLAUDE_SKILL_DIR}/probe.sh:*)"
---

# /skills-check — smoke-тесты интеграций

Быстрая проверка, что внешние системы из `project-index.md` (auto-memory проекта) и `~/.claude/memory/infra-{group}.md` отвечают на канонические запросы data-source скиллов. Нужна, когда URL или API провайдеров могли измениться, токены истечь или профили pcurl разойтись с конвенциями скиллов.

## Использование

```
/skills-check                  # все настроенные интеграции
/skills-check youtrack gitlab  # только перечисленные
/skills-check --verbose        # плюс проверка формы ответа
```

## Пробы

| Секция | Проба (GET) | Заголовок | check для `--verbose` |
|--------|-------------|-----------|------------------------|
| YouTrack | `https://{yt_host}/api/admin/projects?fields=id&$top=1` | `-` | `type == "array"` |
| GitLab | `https://{gl_host}/api/v4/projects/{gl_project_id}?simple=true` | `-` | `.id != null` |
| Sentry | `https://{sentry_host}/api/0/organizations/{org}/projects/?per_page=1` | `-` | `type == "array"` |
| Grafana | `https://{grafana_host}/api/datasources` | `-` | `type == "array"` |
| Prometheus (Grafana proxy) | `https://{grafana_host}/api/datasources/uid/{prom_uid}/resources/api/v1/labels` | `-` | `.status == "success"` |
| Loki (Grafana proxy) | `https://{grafana_host}/api/datasources/uid/{loki_uid}/resources/labels` | `-` | `.status == "success"` |
| Kibana / OpenSearch | `https://{kibana_host}/api/status` | `osd-xsrf: true` | `-` |
| Nomad | `https://{nomad_host}/v1/status/leader` | `-` | `-` |
| API dev/prod | `https://{api_host}/{rpc_endpoint}?smd` | `-` | `.services != null` |

check нужен, потому что прокси или SSO могут вернуть HTTP 200 со страницей логина вместо JSON.

## Порядок

1. Прочитай `project-index.md` и infra-файл. Если project-index нет — предложи пользователю запустить `/onboard` и остановись.
2. Собери строки `name<TAB>profile<TAB>url<TAB>header<TAB>check` по таблице для настроенных секций (или только перечисленных в аргументах). Секции, которых нет в project-index, в таблицу попадут как `SKIP`.
3. Передай строки скрипту (с `--verbose`, если он указан) — он сам проверит профили по `pcurl show`, выполнит GET параллельно (до 6 одновременно), в `--verbose` проверит форму ответа выражением check, не выводя тело (в нём может быть PII), и напечатает таблицу:
   ```bash
   bash ${CLAUDE_SKILL_DIR}/probe.sh [--verbose] <<'EOF'
   youtrack	@{yt_profile}	https://{yt_host}/api/admin/projects?fields=id&$top=1	-	type == "array"
   kibana	@{kibana_profile}	https://{kibana_host}/api/status	osd-xsrf: true	-
   EOF
   ```
4. Выведи таблицу скрипта, добавь SKIP-строки и итог.

## Интерпретация

Скрипт уже подписывает типичные причины: «неожиданный ответ» в `--verbose` — HTTP-код успешный, но ответ не того формата (страница логина прокси, другой API); 401/403 — профиль без доступа или истёкший токен (пользователь обновляет профиль сам через `pcurl add`), 404 — сменился проект, uid или путь API (обновить скилл или project-index), 5xx — проблема провайдера (повторить позже, скилл не чинить), 000 — таймаут, DNS или сеть, `NO-PROFILE` — профиля нет в `pcurl show`.

## Правила

- Только GET: проверка ничего не создаёт и не меняет
- Вывод — простой текст, без цветов, чтобы его можно было скопировать в CI или тикет

## Когда запускать

- После апгрейда Grafana, GitLab или YouTrack (может измениться API)
- После смены профилей pcurl или ротации токенов
- Сразу после `/onboard`
- Периодически, например раз в месяц
