# vmkteam claude-plugins

Marketplace плагинов [Claude Code](https://docs.anthropic.com/en/docs/claude-code) от vmkteam.

## Плагины

| Плагин | Описание |
|--------|----------|
| **[developer](#developer)** | Полный SDLC-профиль для Go API-сервисов — 33 скилла |

---

## developer

Плагин для Go-разработчиков vmkteam. Покрывает полный цикл разработки: от создания проекта и проектирования БД до мониторинга, расследования инцидентов и code review.

## Профиль разработчика vmkteam

vmkteam-developer — это не набор шпаргалок, а **формализованный профиль инженера**, который умеет всё, что нужно для production-ready Go-сервисов.

**Что это значит на практике.** Типичный разработчик знает язык и фреймворк. vmkteam-developer знает весь стек насквозь: от SQL-схемы через кодогенерацию до Prometheus-метрик и Nomad-деплоя. Он не просто пишет код — он решает задачу от тикета до production с артефактами на каждом шаге.

**В чём отличие от обычного AI-ассистента:**

- **Сквозной контекст.** Знает как связаны схема БД, сгенерированный код, RPC-контракт, метрики и алерты. Изменение в одном слое автоматически отражается на всех остальных.
- **Кодогенерация вместо ручного кода.** Не пишет boilerplate — вызывает mfd-generator, colgen, rpcgen, zenrpc. Меньше ручного кода — меньше багов, меньше drift между слоями.
- **Встроенный процесс.** `/solve` — это 11 шагов с 5 точками контроля (HITL). Нельзя закоммитить без ревью. Нельзя реализовать без утверждённого плана. Нельзя планировать без исследования.
- **Multi-persona review.** 6 экспертов с конкретной специализацией: архитектура (Dave Cheney), простота кода (Rob Pike), безопасность (Filippo Valsorda), тесты (Mitchell Hashimoto), операционная готовность (Peter Bourgon).
- **Полный observability.** Один `/investigate` собирает данные из Sentry, Prometheus, Loki, Kibana, Nomad, Grafana параллельно и строит timeline инцидента.
- **Абстрактность.** Все скиллы используют `{placeholders}`. Один `/onboard` — и плагин работает с любым проектом: от стартапа на стадии идеи до production-системы с полным мониторингом.

**Философия:** простой код (Rob Pike), ясные зависимости (Dave Cheney), TDD, spec перед реализацией, документация в git, секреты в keychain, LLM как инструмент — не автор.

## Установка

### Через marketplace (рекомендуется)

```bash
# 1. Добавить marketplace
claude plugin marketplace add vmkteam/claude-plugins

# 2. Установить плагин
claude plugin install vmkteam-developer@vmkteam
```

После установки выполните `/reload-plugins` для активации.

Обновление до новой версии:

```bash
claude plugin update vmkteam-developer@vmkteam
```

### Через --plugin-dir (для разработки)

```bash
claude --plugin-dir ./plugins/developer
```

## Быстрый старт

```bash
# Онбординг в проект — сканирует структуру, спрашивает про инфру, создаёт индекс
/onboard

# Решить задачу из YouTrack — полный цикл
/solve PLF-819

# Code review текущих изменений
/go-review

# Расследовать инцидент
/investigate API тормозит последние 30 минут
```

## Скиллы (33)

### Workflow

| Скилл | Описание |
|-------|----------|
| `/onboard` | Интерактивный онбординг — сканирование, discovery систем, индекс знаний |
| `/solve` | Решение задачи из YouTrack от тикета до коммита (11 шагов, 5 HITL) |
| `/decompose` | Декомпозиция User Story на подзадачи (PO/Dev/QA перспективы) |
| `/commit-msg` | Генерация commit message из git diff |
| `/go-review` | Multi-persona code review (6 экспертов) |
| `/mr-review` | Ревью чужого GitLab MR — fetch diff, review, публикация замечаний |
| `/scaffold` | Создание нового сервиса из шаблона gold-apisrv |

### Справочники по инструментам

| Скилл | Описание |
|-------|----------|
| `/gold-arch` | Архитектура Go-сервисов (3 слоя: db → domain → rpc) |
| `/zenrpc` | JSON-RPC 2.0 сервер — сервисы, middleware, аннотации |
| `/mfd` | MFD-генератор — Go-код из PostgreSQL-схем |
| `/colgen` | Генератор коллекций и конвертеров между слоями |
| `/rpcgen` | Генератор клиентов из SMD/OpenRPC (Go, TypeScript, PHP, Swift, Kotlin, Dart) |
| `/appkit` | Метрики, pprof, HTTP-клиент, service metadata, X-Request-ID |
| `/embedlog` | Встраиваемое структурированное логирование с Prometheus-метриками |
| `/cron` | Менеджер cron-задач с UI, middleware и Prometheus-метриками |
| `/pgd` | Формат pgDesigner |
| `/pgmdd` | Формат MicroOLAP Database Designer |

### Инфраструктура

| Скилл | Описание |
|-------|----------|
| `/ci-cd` | GitLab CI + Nomad deploy |
| `/pgmigrator` | SQL-миграции PostgreSQL |
| `/testing` | Паттерны тестирования — BDD с goconvey, реальная БД, без моков |
| `/security` | Чеклист безопасности для Go-сервисов |

### Источники данных

| Скилл | Описание |
|-------|----------|
| `/youtrack` | Задачи — поиск, создание, обновление через REST API |
| `/gitlab` | MR, pipelines, code review через REST API v4 |
| `/sentry` | Мониторинг ошибок — issues, events, releases |
| `/prometheus` | PromQL-запросы для метрик appkit/zenrpc/cron |
| `/grafana` | Дашборды, Prometheus и Loki proxy через REST API |
| `/loki` | LogQL-запросы для структурированных JSON-логов |
| `/kibana` | Kibana/OpenSearch Dashboards — поиск по логам |
| `/nomad` | Оркестрация — jobs, allocations, метрики |
| `/api-health` | Health checks JSON-RPC, SMD discovery, тайминги |

### Оркестраторы

| Скилл | Описание |
|-------|----------|
| `/investigate` | Расследование инцидента по всем источникам данных |
| `/incident` | Реакция на инцидент — сбор данных, timeline, root cause, hotfix, post-mortem |
| `/errors` | Дайджест ошибок за период из Sentry, Prometheus, Loki, Kibana |
| `/philosophy` | Манифест разработки vmkteam — принципы и культура |

## Архитектура

```
vmkteam/claude-plugins/
├── .claude-plugin/
│   └── marketplace.json          # Каталог marketplace
├── plugins/
│   └── developer/                # Плагин vmkteam-developer
│       ├── .claude-plugin/
│       │   └── plugin.json       # Метаданные плагина
│       └── skills/
│           ├── onboard/SKILL.md
│           ├── solve/SKILL.md
│           ├── go-review/SKILL.md
│           └── .../SKILL.md      # ещё 30 скиллов
├── LICENSE
└── README.md
```

### Как работает онбординг

`/onboard` создаёт два файла:

- **`~/.claude/memory/infra-{group}.md`** — общая инфраструктура группы (GitLab, YouTrack, Sentry, Grafana, Prometheus, Loki, Kibana, Nomad). Один файл на группу, переиспользуется всеми проектами.
- **`{project-auto-memory}/project-index.md`** — специфика сервиса (endpoints, jobs, slugs, MFD namespaces, связанные сервисы).

Остальные скиллы читают оба файла и подставляют `{placeholders}` конкретными значениями.

### Стадии проекта

| Стадия | Описание | Доступные системы |
|--------|----------|-------------------|
| **Идея** | Только код, нет деплоя | YouTrack, Git |
| **Dev** | Задеплоен на dev/staging | + Sentry, API dev, возможно Grafana |
| **Production** | Задеплоен на prod | + Sentry, Grafana, Prometheus, Loki, Nomad, Kibana |

### Внешние инструменты

Все HTTP-запросы к внешним системам идут через **pcurl** — CLI-обёртка, хранящая credentials в OS keychain. Скиллы никогда не работают с секретами напрямую.

## Требования

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI
- [pcurl](https://github.com/vmkteam/pcurl) для аутентифицированного доступа к API
- Go 1.21+ и vmkteam toolchain (для скиллов кодогенерации)

## Лицензия

[MIT](LICENSE)
