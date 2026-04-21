---
name: ci-cd
description: "CI/CD — GitLab CI + Nomad deploy для Go-сервисов vmkteam. Используй при редактировании .gitlab-ci.yml, *.nomad.hcl, настройке пайплайна или дебаге деплоя."
---

# CI/CD — Pipeline и Deploy

GitLab CI + Docker + Nomad. Pipeline настроен автоматически, вмешательство не требуется.

## Ветвление и деплой

| Ветка | Окружение | Deploy |
|-------|-----------|--------|
| `devel` | Dev/Staging | Автоматический (merge/push → deploy) |
| `master` | Production | Автоматический (merge/push → deploy) |
| остальные | — | Только CI (lint/test/security) |

## Nomad

Конфиги деплоя в `deployments/`:

```
deployments/
├── service.devel.nomad.hcl   # Job spec для devel
├── service.master.nomad.hcl  # Job spec для production
├── devel.vars.hcl            # Переменные devel (count, cpu, memory)
└── master.vars.hcl           # Переменные production
```

Переменные в `.vars.hcl` — ресурсы (cpu, memory), количество инстансов (count), версия образа.

## CI Pipeline (справочно)

Стадии: lint → test → security → build → deploy.

Security checks:

| Инструмент | Что проверяет |
|-----------|--------------|
| `gitleaks` | Утечки секретов |
| `gosec` | Уязвимости в Go коде |
| `govulncheck` | Уязвимости в зависимостях |
| `trivy` | Уязвимости в Docker образах |
