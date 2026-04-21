---
name: skills-check
description: "Skills Check — smoke-тесты интеграций из project-index.md. Используй для проверки что pcurl-профили и URL всех data-source скиллов ещё живы."
---

# /skills-check — smoke-тесты интеграций

Быстрая проверка, что внешние системы, описанные в `project-index.md` и `infra-{group}.md`, отвечают на канонические запросы data-source скиллов. Нужен когда URL/API провайдеров могли измениться, токены истечь или профили pcurl разойтись со skill-конвенциями.

## Использование

```
/skills-check                  # все настроенные интеграции
/skills-check youtrack gitlab  # только перечисленные
/skills-check --verbose        # печатать полный ответ, а не только HTTP-код
```

## Что проверяется

Читает `{project-auto-memory}/project-index.md` и подключённый infra-файл. Для каждой секции запускает минимальный пробник:

| Секция | Проба | OK-признак |
|--------|-------|-----------|
| YouTrack | `GET /api/admin/projects?fields=id&$top=1` | HTTP 200, `[]` массив |
| GitLab | `GET /api/v4/projects/{gl_project_id}?simple=true` | HTTP 200, `.id` |
| Sentry | `GET /api/0/organizations/{org}/projects/?per_page=1` | HTTP 200 |
| Grafana | `GET /api/datasources` | HTTP 200, массив |
| Prometheus (Grafana proxy) | `GET /api/datasources/uid/{uid}/resources/api/v1/labels` | HTTP 200, `.status=="success"` |
| Loki (Grafana proxy) | `GET /api/datasources/uid/{uid}/resources/labels` | HTTP 200, `.status=="success"` |
| Kibana/OpenSearch | `GET /api/status` с `osd-xsrf: true` | HTTP 200 |
| Nomad | `GET /v1/status/leader` | HTTP 200 |
| API dev/prod | `GET {rpc_endpoint}?smd` | HTTP 200, валидный JSON с `.services` |

Также кросс-проверяется, что все упомянутые в project-index pcurl-профили есть в `pcurl show` — несовпадение = профиль не создан локально.

## Порядок выполнения

1. Прочитать `project-index.md` и `infra-{group}.md`
2. Собрать список (скилл, профиль, URL, ожидаемый shape)
3. Запустить пробники **параллельно** (через `&` + `wait` или через xargs)
4. Собрать результаты в таблицу

## Шаблон пробника

```bash
# Шаблон: silent, только HTTP-код + время
pcurl @{profile} '{url}' -s -o /dev/null -w '%{http_code} %{time_total}\n'
```

Для verbose — без `-o /dev/null`, плюс `jq '.' | head -5` для первых строк ответа.

## Интерпретация

- **2xx/3xx** — OK
- **401/403** — профиль pcurl не имеет доступа или токен истёк. Пользователь обновляет профиль (`pcurl add`)
- **404** — URL уехал: либо проект пересоздан, либо API провайдера поменял путь → обновить скилл или project-index
- **5xx** — сервер провайдера. Повторить позже, не чинить скилл
- **таймаут/DNS** — хост недоступен. Проверить VPN/сеть
- **профиль не найден в `pcurl show`** — сказать пользователю: `pcurl add` для этого хоста

## Формат вывода

```
Skill          Status   Code  Latency   Note
─────────────────────────────────────────────────────
youtrack       ✓ OK     200    120ms
gitlab         ✓ OK     200     45ms
sentry         ✗ FAIL   401             token истёк?
grafana        ✓ OK     200     80ms
prometheus     ✓ OK     200     95ms
loki           ✗ FAIL   404             datasource uid изменился?
api-dev        ✓ OK     200    210ms    SMD: 47 сервисов
api-prod       - SKIP                   не настроен в project-index
─────────────────────────────────────────────────────
7/9 OK, 2 требуют внимания
```

## Правила

- Никаких mutating-запросов (только GET). Skill-check не должен ничего создавать/менять
- Не логировать ответы целиком — могут содержать PII. Только status + shape-маркер
- Параллельно, но с ограничением (одновременно не более 6 запросов)
- Если `project-index.md` отсутствует — подсказать запустить `/onboard`
- Вывод копируется как текст — никаких цветов/эмодзи-наворотов в CI-контексте

## Когда запускать

- После апгрейда Grafana/GitLab/YouTrack (может измениться API)
- После смены профилей pcurl или ротации токенов
- Первый раз после `/onboard` (дымовой тест)
- Периодически — раз в месяц или через `/loop 30d /skills-check`
