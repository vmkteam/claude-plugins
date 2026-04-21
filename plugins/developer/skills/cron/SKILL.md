---
name: cron
description: "Cron — менеджер cron-задач с UI, middleware и Prometheus-метриками. Используй при добавлении/правке cron-задачи, подключении пакета vmkteam/cron или настройке CronConfig."
---

# Cron

- Upstream: https://github.com/vmkteam/cron
- Обёртка над robfig/cron: context-aware jobs, web UI, ручной запуск, middleware, метрики
- Сигнатура задачи: `func(ctx context.Context) error`

## Базовый шаблон

```go
m := cron.NewManager()
m.Use(
    cron.WithMetrics("mysrv"),
    cron.WithDevel(cfg.IsDevel),
    cron.WithSLog(logger),
    cron.WithMaintenance(log.Printf),
    cron.WithSkipActive(),
    cron.WithRecover(),
    cron.WithSentry(),
)

m.AddFunc("sync-users", "*/5 * * * *", func(ctx context.Context) error { ... })
m.AddMaintenanceFunc("db-vacuum", "0 4 * * 0", ...)   // эксклюзивный, блокирует остальные
m.AddFunc("manual-import", "", ...)                    // "" = только ручной запуск

go m.Run(ctx)
http.HandleFunc("/debug/cron", m.Handler)
```

## Middleware

| MW | Назначение |
|----|------------|
| `WithMetrics(serverName)` | Prometheus (count/duration/active) |
| `WithSLog(logger)` | structured logging |
| `WithLogger(printf, serverName)` | legacy Printf |
| `WithSentry()` | ошибки + panic recovery → Sentry |
| `WithRecover()` | panic recovery (альтернатива WithSentry) |
| `WithDevel(isDevel)` | dev-флаг в ctx |
| `WithSkipActive()` | **обязателен для длинных задач** — пропуск если предыдущий запуск ещё идёт |
| `WithMaintenance(printf)` | эксклюзивное выполнение maintenance-задач |

## Метрики

- `app_cron_evaluated_total` — counter выполнений по состояниям
- `app_cron_active` — gauge активных задач
- `app_cron_evaluated_duration_seconds` — summary длительности

## UI / API

- `GET /debug/cron` — HTML расписание (имя, паттерн, next, state, duration)
- `GET /debug/cron` с `Accept: application/json` — JSON
- `GET /debug/cron?start=<name>` — ручной запуск (follow redirect)

## VT-конвенция: расписания в TOML

Schedule = string (type `cron.Schedule`), выносится в `CronConfig`, не хардкодится:

```go
// pkg/app/app.go
type CronConfig struct {
    SyncUsersTime    cron.Schedule  // "*/5 * * * *"
    CleanupTime      cron.Schedule  // "0 3 * * *"
    ExportTime       cron.Schedule  // "0 4 * * 0"
    ManualImportTime cron.Schedule  // "" — только UI
}
```

```toml
# cfg/local.toml
[Cron]
SyncUsersTime = "*/5 * * * *"
CleanupTime = "0 3 * * *"
ManualImportTime = ""
```

Отдельный `pkg/app/cron.go` с `newCron()`, задачи делегируют в daemon/manager:

```go
func (a *App) newCron() *cron.Manager {
    m := cron.NewManager()
    m.Use(
        cron.WithMetrics(a.appName),
        cron.WithSLog(a.Logger),
        cron.WithSkipActive(),
        cron.WithSentry(),
    )
    cc := a.cfg.Cron
    m.AddFunc("sync.users", cc.SyncUsersTime, a.daemon.SyncUsers)
    m.AddFunc("cleanup", cc.CleanupTime, a.daemon.Cleanup)
    m.AddFunc("export", cc.ExportTime, a.daemon.Export)
    m.AddFunc("manual.import", cc.ManualImportTime, a.daemon.Import)
    return m
}

// Run
a.cron = a.newCron()
go a.cron.Run(ctx)
a.echo.GET("/debug/cron", echo.WrapHandler(http.HandlerFunc(a.cron.Handler)))
```

Правила: группы задач с комментариями по доменам; имена через точку (`sync.users`, `manual.import`); `""` = ручной запуск.
