---
name: philosophy
description: "Philosophy — манифест разработки vmkteam. Принципы, культура, подходы."
---

# Philosophy — манифест vmkteam

Принципы разработки vmkteam. Источник: https://vmkteam.dev

## Код

- Пиши простой код. Думай о том, кто будет его читать через год
- Кодогенерация лучше ручного кода. Меньше ручного кода — меньше багов
- Не используй интерфейсы без необходимости. Конкретные типы понятнее
- Каждый слой имеет свои модели. Конвертеры между слоями обязательны
- Три строки простого кода лучше одной умной абстракции

## Архитектура

- Simple Architecture: DB → Domain → API, JSON-RPC 2.0 (/gold-arch)
- Не делай domain-слой для простого CRUD
- DI через конструкторы. Никакого global state
- Документация в git, не в Confluence. ADR для решений
- C4-диаграммы из метрик Prometheus (genc4)

## Процесс

- Планируй перед кодом. Spec перед реализацией (/solve)
- Тесты перед кодом — TDD (/testing)
- Ревью обязателен, даже собственного кода (/go-review)
- Коммиты с номером задачи (/commit-msg)
- Не деплой в пятницу

## Безопасность

- Валидируй на границе системы (/security)
- Секреты в OS keychain (pcurl) или env vars. Никогда в коде
- gosec, govulncheck, gitleaks в CI (/ci-cd)

## LLM и автоматизация

- LLM — инструмент, не автор. Код должен быть понятен без AI
- Кодогенерация с AI допустима когда: есть спецификация, результат проверяем тестами, код следует паттернам проекта
- Артефакты LLM сохраняются в `docs/llm/` (`tasks/` для задач, `incidents/` для инцидентов) — прозрачность процесса
- Не создавай зависимость от LLM

## Стадии проекта

| Стадия | БД | Миграции | Мониторинг |
|--------|-----|----------|-----------|
| Идея | sql файл актуальный, `make db` с нуля | Нет | Нет |
| Dev | + pgmigrator, sql всё ещё актуальный | Да | Sentry, возможно Prometheus |
| Production | + полный мониторинг | Да | Sentry, Prometheus, Loki, Grafana, Nomad |

## Ссылки

- https://vmkteam.dev/simple-architecture/ — Simple Architecture
- https://vmkteam.dev/development/philosophy/ — принципы
- https://vmkteam.dev/development/mastering-api/ — работа с API
- https://github.com/vmkteam — инструменты
