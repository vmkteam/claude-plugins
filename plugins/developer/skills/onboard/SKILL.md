---
name: onboard
description: "Onboard — интерактивный онбординг в проект. Сканирует структуру, обнаруживает системы, создаёт индекс знаний."
---

# Onboard — интерактивный онбординг в проект

Интерактивный процесс изучения проекта. Сканирует структуру, обнаруживает системы, создаёт индексный файл знаний для всех скиллов плагина vmkteam-developer.

## Процесс

### Шаг 1. Сканирование проекта

Изучи локальную структуру:
- `go.mod` — модуль, зависимости, Go-версия, vmkteam-зависимости
- `Makefile` / `Makefile.mk` — доступные команды, генераторы
- `docs/model/*.mfd` — MFD-схема, namespace'ы, таблицы
- `docs/*.pgd` / `docs/*.pdd` — схема БД (определяет: /pgd или /pgmdd)
- `pkg/` — структура пакетов (db, rpc, vt, domain)
- `cmd/` — точки входа, бинарники
- `.gitlab-ci.yml` — CI/CD pipeline
- `deployments/` — Nomad/Docker конфиги
- `cfg/` — конфигурация (TOML)
- `migrations/` — SQL миграции
- `CLAUDE.md` / `.claude/` — существующие инструкции

Автоопределение vmkteam-инструментов из go.mod:
- `vmkteam/zenrpc` → скилл /zenrpc
- `vmkteam/mfd-generator` (или Makefile mfd-*) → скилл /mfd
- `vmkteam/colgen` (или `//go:generate colgen`) → скилл /colgen
- `vmkteam/rpcgen` (или Makefile *-client) → скилл /rpcgen
- `vmkteam/appkit` → скилл /appkit
- `vmkteam/cron` → скилл /cron
- `vmkteam/zenrpc-middleware` → скилл /zenrpc
- `.pgd` файлы → скилл /pgd
- `.pdd` файлы → скилл /pgmdd

Определи тип сервиса: API, worker, cron, hybrid.

### Шаг 2. Определить стадию и infra-группу

Спроси у пользователя:

1. **На какой стадии проект?**

| Стадия | Описание | Доступные системы |
|--------|----------|-------------------|
| **Идея** | Только код, нет деплоя | YouTrack, Git |
| **Dev** | Задеплоен на dev/staging | + Sentry (dev), API dev, возможно Grafana |
| **Production** | Задеплоен на prod | + Sentry (prod), API prod, Grafana, Prometheus, Loki, Nomad |

Стадия определяет какие системы спрашивать — не задавай вопросы про Grafana/Prometheus если проект на стадии "Идея".

2. **К какой infra-группе относится проект?** (например: acme, platform, storefront)

Проверить наличие shared infra-файла: `~/.claude/memory/infra-{group}.md`
- **Если существует** — показать содержимое, спросить актуально ли. Перейти к шагу 3b (только специфика сервиса).
- **Если не существует** — перейти к шагу 3a (полный опрос), создать infra-файл.

### Шаг 3a. Полный опрос (новая infra-группа)

Спрашивай только системы, релевантные стадии.

#### Infra-level (общие для всех сервисов группы):
1. **GitLab**: Какой GitLab-инстанс? pcurl-профиль? Username?
2. **YouTrack**: Какой YouTrack-инстанс? pcurl-профиль?
3. **Sentry** (Dev+): pcurl-профиль, org? Sentry общий для dev и prod или раздельный?
4. **Grafana** (Production): pcurl-профиль?
5. **Prometheus** (Dev+): pcurl-профиль (dev)? pcurl-профиль (prod, если отличается)?
6. **Loki** (Production): через Grafana? loki datasource UID?
7. **Kibana** (Production): pcurl-профиль? Тип (opensearch/kibana)?
8. **Nomad** (Production): pcurl-профиль?
9. **Ветвление**: общая модель (devel→staging, master→production)?

#### Service-level (специфика этого сервиса):
10. **YouTrack проект**: shortName, project_id, state_field и значения?
11. **GitLab project**: Project ID, path?
12. **Sentry project**: slug?
13. **Prometheus job**: имя job для этого сервиса?
14. **Loki service_name**: имя в Loki?
15. **Grafana dashboard**: UID дашборда?
16. **API endpoints**: URL dev/prod, pcurl-профили, rpc_endpoint?
17. **Nomad job**: имя job?
18. **Специфика**: особые правила, code style?
19. **Артефакты /solve** (`artifacts`): коммитить `docs/llm/tasks/` вместе с MR или публиковать как коммент со спойлерами? Варианты:
    - `commit` — артефакты коммитятся в ветку (по умолчанию)
    - `comment` — артефакты публикуются как коммент в MR (GitLab) или задачу (YouTrack)

### Шаг 3b. Краткий опрос (infra-группа уже есть)

Спрашивать только service-level (пп. 10-18 из шага 3a). Infra-level берётся из `~/.claude/memory/infra-{group}.md`.

### Шаг 4. Проверка подключений

Если infra-файл уже существует — проверять только service-specific endpoints (API dev/prod, Sentry project, Prometheus job). Infra-level проверки (GitLab, YouTrack, Grafana) уже пройдены.

Для новой infra-группы — проверить все. Все проверки ПАРАЛЛЕЛЬНО:

```bash
# YouTrack — проекты и кастомные поля (state может называться иначе: Stage, Status и т.д.)
pcurl @{yt_profile} 'https://{yt_host}/api/admin/projects?fields=id,shortName,name&$top=50' -s -o /dev/null -w '%{http_code}'

# GitLab — проект и доступ
pcurl @{gl_profile} 'https://{gl_host}/api/v4/projects/{gl_project_id}?simple=true' -s -o /dev/null -w '%{http_code}'

# Sentry
pcurl @{sentry_profile} 'https://{sentry_host}/api/0/organizations/{org}/projects/' -s -o /dev/null -w '%{http_code}'

# Grafana
pcurl @{grafana_profile} 'https://{grafana_host}/api/health' -s -o /dev/null -w '%{http_code}'

# Prometheus
pcurl @{prom_profile} 'https://{prom_host}/api/v1/query?query=up' -s -o /dev/null -w '%{http_code}'

# Loki (через Grafana)
pcurl @{grafana_profile} 'https://{grafana_host}/api/datasources/uid/{loki_uid}/resources/labels' -s -o /dev/null -w '%{http_code}'

# API prod (/status скрыт за firewall — проверяем RPC endpoint)
pcurl @{api_prod_profile} 'https://{api_prod_host}/{rpc_endpoint}?smd' -s -o /dev/null -w '%{http_code}'

# API dev
pcurl @{api_dev_profile} 'https://{api_dev_host}/{rpc_endpoint}?smd' -s -o /dev/null -w '%{http_code}'
```

### Шаг 5. Discovery (если проверки прошли)

Параллельно собрать:
```bash
# Sentry: проекты (полная карта сервисов организации)
pcurl @{sentry_profile} 'https://{sentry_host}/api/0/organizations/{org}/projects/' -s

# Grafana: дашборды и datasources
pcurl @{grafana_profile} 'https://{grafana_host}/api/search?type=dash-db&query={service}' -s
pcurl @{grafana_profile} 'https://{grafana_host}/api/datasources' -s

# Prometheus: jobs и межсервисная топология
pcurl @{prom_profile} 'https://{prom_host}/api/v1/label/job/values' -s
pcurl @{prom_profile} 'https://{prom_host}/api/v1/query' -s -G --data-urlencode 'query=app_metadata_services'
pcurl @{prom_profile} 'https://{prom_host}/api/v1/query' -s -G --data-urlencode 'query=app_metadata_db_connections_total'

# Loki: сервисы (UID-based путь — /resources/ без /loki/api/v1/)
pcurl @{grafana_profile} 'https://{grafana_host}/api/datasources/uid/{loki_uid}/resources/label/service_name/values' -s

# YouTrack: кастомные поля и значения state (может быть Stage, Status etc.)
pcurl @{yt_profile} 'https://{yt_host}/api/issues?query=project:{PROJECT}&fields=idReadable,customFields(name,value(name))&$top=5' -s

# API: SMD (список RPC namespace'ов и методов) — через ?smd
pcurl @{api_prod_profile} 'https://{api_prod_host}/{rpc_endpoint}?smd' -s -L
```

### Шаг 5b. Multi-repo и Architecture discovery

Определить связанные сервисы из нескольких источников:

```bash
# Из pkg/client/ — rpcgen-клиенты
ls pkg/client/ 2>/dev/null

# Из конфигов — URL других сервисов
grep -r 'http://' cfg/local.toml.dist 2>/dev/null
```

Из Prometheus (Dev и выше) — построить топологию через метрики appkit:

```bash
# Какие сервисы существуют
pcurl @{prom_profile} 'https://{prom_host}/api/v1/query' -s -G --data-urlencode 'query=app_metadata_service'

# Межсервисные связи (sync/async/external)
pcurl @{prom_profile} 'https://{prom_host}/api/v1/query' -s -G --data-urlencode 'query=app_metadata_services'

# Подключения к БД
pcurl @{prom_profile} 'https://{prom_host}/api/v1/query' -s -G --data-urlencode 'query=app_metadata_db_connections_total'
```

Из этих метрик собрать полную карту: какой сервис с кем общается (sync/async), какие БД использует.

Для каждого связанного сервиса проверить наличие локальных исходников.

### Шаг 6. Генерация файлов

Онбординг создаёт два файла в **РАЗНЫХ** директориях:

| Файл | Абсолютный путь | Scope | Инструмент |
|------|-----------------|-------|------------|
| **Shared infra** | `~/.claude/memory/infra-{group}.md` | Глобальный (все проекты группы) | Write (абсолютный путь, mkdir -p если нет) |
| **Project index** | `{project-auto-memory-dir}/project-index.md` | Только этот проект | Write (в auto-memory директорию проекта) |

**ВАЖНО:**
- `~/.claude/memory/` — это **глобальная** директория, НЕ auto-memory проекта. Создай её через `mkdir -p ~/.claude/memory/` если не существует.
- `{project-auto-memory-dir}` — это auto-memory директория текущего проекта (например `~/.claude/projects/-Users-username-Projects-Go-foo/memory/`). Используй Write tool с абсолютным путём.
- **НЕ путай** эти директории. Infra-файл должен быть доступен из ЛЮБОГО проекта группы.
- Скиллы читают оба файла. Infra-level значения берутся из `infra-{group}.md`, service-level — из `project-index.md`. Скиллы подставляют значения вместо `{placeholders}`.

#### 6a. Shared infra: `~/.claude/memory/infra-{group}.md`

Создаётся один раз для infra-группы. При повторном онбординге — обновляется только если что-то изменилось. Путь всегда абсолютный: `~/.claude/memory/infra-{group}.md`.

```markdown
# infra-{group} — shared infrastructure

## GitLab
- profile: @{gl_profile}
- host: {gl_host}
- username: {gl_username}

## YouTrack
- profile: @{yt_profile}
- host: {yt_host}

## Sentry
- profile: @{sentry_profile}
- host: {sentry_host}
- org: {org}

## Grafana
- profile: @{grafana_profile}
- host: {grafana_host}
- prometheus_datasource_uid: {uid}
- loki_datasource_uid: {uid}

## Prometheus
- profile_dev: @{prom_dev_profile}
- host_dev: {prom_dev_host}
- profile_prod: @{prom_prod_profile}
- host_prod: {prom_prod_host}

## Loki
- via grafana proxy (UID-based: /resources/query_range, НЕ /loki/api/v1/)
- loki_uid: {uid}

## Kibana / OpenSearch Dashboards (если есть)
- profile: @{kibana_profile}
- host: {kibana_host}
- type: {opensearch / kibana}

## Nomad (если есть)
- profile: @{nomad_profile}
- host: {nomad_host}

## Ветвление
- devel → staging (auto deploy)
- master → production (auto deploy)
```

#### 6b. Project index: `{project-auto-memory-dir}/project-index.md`

Путь: auto-memory директория текущего проекта (абсолютный). Строка `infra:` в начале файла указывает на shared infra-файл.

```markdown
# {Project} — индекс знаний

infra: ~/.claude/memory/infra-{group}.md

## Общая информация
- Модуль: {module}
- Go: {version}
- Тип: {API/worker/hybrid}
- Стадия: {Идея/Dev/Production}
- Деплой: {Nomad/Docker/K8s / нет}

## Структура
- DB: pkg/db/ ({N} сущностей, {namespaces})
- Domain: pkg/{name}/ (есть/нет)
- RPC: pkg/rpc/ ({N} сервисов, namespace: {ns}, endpoint: /rpc/)
- VT: pkg/vt/ ({N} сервисов, endpoint: /vt/)
- Migrations: docs/patches/ ({N} файлов)

## Инструменты vmkteam
- zenrpc {version}
- mfd-generator {version} (MFD: docs/model/{name}.mfd)
- colgen (//go:generate colgen в pkg/rpc/, pkg/vt/)
- rpcgen {version}
- appkit {version}
- cron (есть/нет)

## Релевантные скиллы
- /gold-arch — архитектура (трёхслойная)
- /zenrpc — RPC-методы, middleware, аннотации
- /mfd — генерация из БД (namespaces: {list})
- /colgen — коллекции и конвертеры
- /pgd или /pgmdd — схема БД ({file})
- /rpcgen — генерация клиентов
- /appkit — метрики, pprof, embedlog
- /pgmigrator — SQL миграции
- /testing — тесты (pkg/db/test/)
- /commit-msg — коммиты
- /go-review — code review (свой код)
- /mr-review — ревью чужих MR
- /gitlab — MR, pipelines, discussions
- /incident — реакция на production инциденты

## Service systems

### GitLab project
- project_id: {gl_project_id}
- project_path: {group/project}
- url: https://{gl_host}/{group/project}/-/merge_requests

### YouTrack project
- project: {SHORT}
- project_id: {id}
- state_field: {State/Stage/Status}
- state_open: {Open/Backlog/...}
- state_done: {Done/Closed/...}
- url: https://{yt_host}/issues?q=project:{SHORT}

### Sentry project
- project_slug: {slug}
- url: https://{sentry_host}/organizations/{org}/issues/?project={project_id}

### Prometheus
- job: {service_job_name}

### Loki
- service_name: {service_name_in_loki}

### Grafana dashboard
- dashboard_uid: {uid}
- dashboard_url: https://{grafana_host}/d/{uid}

### Kibana (если есть)
- index_patterns: {nginx-access-*, nginx-error-*, ...}

### Nomad (если есть)
- job: {nomad_job_name}

### API Production
- profile: @{api_prod_profile}
- host: {api_prod_host}
- rpc_endpoint: /rpc/
- vt_endpoint: /vt/

### API Dev/Staging
- profile: @{api_dev_profile}
- host: {api_dev_host}
- rpc_endpoint: /rpc/

## Solve settings
- artifacts: {commit/comment} — куда складывать артефакты /solve (docs/llm/tasks/)

## Makefile-команды
{список ключевых make targets с кратким описанием}

## Связанные сервисы
| Сервис | Тип связи | Локальный путь | Sentry slug | Prometheus job |
|--------|-----------|----------------|-------------|----------------|
| {service} | {sync/async/db} | {path} | {slug} | {job} |

## Локальные пути
- Исходники: {path}
- Связанные проекты: {list}
```

### Шаг 7. Валидация

Покажи пользователю сгенерированный индекс и попроси подтвердить/уточнить.

## Результат

После онбординга:
- `~/.claude/memory/infra-{group}.md` содержит общие подключения (GitLab, YouTrack, Sentry, Grafana, Prometheus, Loki, Kibana, Nomad)
- `.claude/memory/project-index.md` содержит специфику сервиса и ссылку на infra-файл
- Скиллы читают оба файла: infra-level из `infra-{group}.md`, service-level из `project-index.md`
- Повторный онбординг сервиса той же группы — только service-level вопросы
