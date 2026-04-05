---
name: cron
description: "Cron — менеджер cron-задач для Go с UI, middleware и Prometheus метриками."
---

# Cron — менеджер cron-задач

cron (https://github.com/vmkteam/cron) — менеджер cron-задач на базе robfig/cron с расширенными возможностями для production.

## Ключевые возможности

- **Context-aware jobs** — сигнатура `func(ctx context.Context) error`
- **Встроенный UI** — веб-интерфейс мониторинга и управления
- **Ручной запуск** — API для on-demand выполнения
- **Middleware** — расширяемый pipeline обработки
- **Состояния** — детальный мониторинг статуса задач
- **Визуализация расписания** — через curl или UI

## Использование

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

// Обычные задачи
m.AddFunc("sync-users", "*/5 * * * *", func(ctx context.Context) error {
    return mgr.SyncUsers(ctx)
})

m.AddFunc("cleanup", "0 3 * * *", func(ctx context.Context) error {
    return mgr.Cleanup(ctx)
})

// Maintenance задача (блокирует остальные на время выполнения)
m.AddMaintenanceFunc("db-vacuum", "0 4 * * 0", func(ctx context.Context) error {
    return mgr.Vacuum(ctx)
})

// Задача без расписания (только ручной запуск)
m.AddFunc("manual-import", "", func(ctx context.Context) error {
    return mgr.Import(ctx)
})

// Запуск
go func() {
    if err := m.Run(ctx); err != nil {
        log.Fatal(err)
    }
}()

// UI handler
http.HandleFunc("/debug/cron", m.Handler)
```

## Middleware

| Middleware | Что делает |
|-----------|-----------|
| `WithMetrics(serverName)` | Prometheus метрики (count, duration, active) |
| `WithSLog(logger)` | Structured logging через slog |
| `WithLogger(printf, serverName)` | Legacy Printf-style логирование |
| `WithSentry()` | Отправка ошибок в Sentry + panic recovery |
| `WithRecover()` | Panic recovery (альтернатива Sentry) |
| `WithDevel(isDevel)` | Флаг dev-окружения в контексте |
| `WithSkipActive()` | Пропускает запуск если задача ещё выполняется |
| `WithMaintenance(printf)` | Эксклюзивное выполнение maintenance-задач |

## Prometheus метрики

| Метрика | Тип | Описание |
|---------|-----|----------|
| `app_cron_evaluated_total` | counter | Всего выполнений по состояниям |
| `app_cron_active` | gauge | Активные задачи сейчас |
| `app_cron_evaluated_duration_seconds` | summary | Длительность выполнения |

## UI и curl

```bash
# Расписание (текст)
curl http://localhost:{port}/debug/cron

# Расписание (JSON)
curl -H 'Accept: application/json' http://localhost:{port}/debug/cron

# Ручной запуск задачи
curl -L http://localhost:{port}/debug/cron?start=sync-users
```

UI показывает: имя задачи, cron-паттерн, следующее выполнение, состояние, длительность.

## Интеграция в App (паттерн из production)

### CronConfig — расписание в TOML

Расписания выносятся в конфиг (`cron.Schedule` = string), не хардкодятся:

```go
// pkg/app/app.go
type CronConfig struct {
    SyncUsersTime       cron.Schedule  // "*/5 * * * *"
    CleanupTime         cron.Schedule  // "0 3 * * *"
    ExportTime          cron.Schedule  // "0 4 * * 0"
    ManualImportTime    cron.Schedule  // "" (только ручной запуск)
}
```

```toml
# cfg/local.toml
[Cron]
SyncUsersTime = "*/5 * * * *"
CleanupTime = "0 3 * * *"
ExportTime = "0 4 * * 0"
ManualImportTime = ""
```

### Отдельный файл cron.go

```go
// pkg/app/cron.go
func (a *App) newCron() *cron.Manager {
    m := cron.NewManager()
    m.Use(
        cron.WithMetrics(a.appName),
        cron.WithSLog(a.Logger),
        cron.WithSkipActive(),
        cron.WithSentry(),
    )

    cc := a.cfg.Cron

    // sync
    m.AddFunc("sync.users", cc.SyncUsersTime, a.daemon.SyncUsers)
    m.AddFunc("cleanup", cc.CleanupTime, a.daemon.Cleanup)

    // exports
    m.AddFunc("export", cc.ExportTime, a.daemon.Export)

    // manual only
    m.AddFunc("manual.import", cc.ManualImportTime, a.daemon.Import)

    return m
}
```

### Запуск и UI

```go
// pkg/app/app.go
func (a *App) Run(ctx context.Context) error {
    a.cron = a.newCron()
    go a.cron.Run(ctx)

    // UI на /debug/cron
    a.echo.GET("/debug/cron", echo.WrapHandler(http.HandlerFunc(a.cron.Handler)))

    return a.echo.Start(addr)
}
```

### Правила

- Расписания в CronConfig (TOML), не хардкод
- Задачи группируются по доменам с комментариями
- Методы cron делегируют напрямую в daemon/manager
- `WithSkipActive()` — обязателен для длинных задач
- Пустая строка `""` — задача без расписания (только через UI)
```

## Паттерны cron-выражений

| Паттерн | Описание |
|---------|----------|
| `* * * * *` | Каждую минуту |
| `*/5 * * * *` | Каждые 5 минут |
| `0 * * * *` | Каждый час |
| `0 3 * * *` | Каждый день в 3:00 |
| `0 4 * * 0` | Каждое воскресенье в 4:00 |
| `""` (пустая строка) | Только ручной запуск |
