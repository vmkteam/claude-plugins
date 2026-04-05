---
name: appkit
description: "Appkit — справочник по vmkteam/appkit: метрики, pprof, HTTP client, service metadata, X-Request-ID."
---

# Appkit — инфраструктурный toolkit

vmkteam/appkit (https://github.com/vmkteam/appkit) — набор middleware и утилит для Go-сервисов.

Связанные скиллы: /embedlog (логирование), /cron (cron-задачи), /prometheus (PromQL запросы к метрикам appkit).

## Компоненты

### Метрики (Prometheus)

Appkit автоматически регистрирует метрики `app_*`:

```go
import "github.com/vmkteam/appkit/metrics"

func (a *App) registerMetrics() {
    metrics.Register(a.echo) // /metrics endpoint
}
```

Server-метрики:
- `app_http_requests_total` — HTTP запросы (labels: job, code, method, uri, server)
- `app_http_responses_duration_seconds_*` — HTTP latency

Client-метрики (исходящие запросы):
- `app_http_client_requests_total` — исходящие HTTP запросы
- `app_http_client_requests_inflight` — текущие исходящие
- `app_http_client_responses_duration_seconds_*` — latency исходящих

Metadata-метрики:
- `app_metadata_service` — информация о сервисе (version, зависимости)
- `app_metadata_services` — связи между сервисами (sync/async/external)
- `app_metadata_db_connections_total` — подключения к БД
- `app_log_events_total` — log events (info/error)

### Service Metadata

Декларация зависимостей сервиса для auto-discovery (используется в /onboard и /investigate):

```go
import "github.com/vmkteam/appkit/metadata"

func (a *App) registerMetadata() {
    md := metadata.New(a.appName, version)

    // БД
    md.AddDatabase("postgres", a.db.PoolStats)

    // Зависимые сервисы (sync)
    md.AddService("{dep_service}", metadata.Sync)

    // Async (NATS, RabbitMQ)
    md.AddService("{async_service}", metadata.Async)

    // Внешние сервисы
    md.AddService("{ext_service}", metadata.External)

    md.Register() // регистрирует Prometheus метрики
}
```

### HTTP Client с метриками

Исходящие HTTP-запросы к другим сервисам с автоматическими метриками и internal headers:

```go
import "github.com/vmkteam/appkit/httpclient"

// Создание клиента с метриками и internal headers
client := httpclient.New(
    httpclient.WithMetrics("caller-service"),
    httpclient.WithInternalHeaders(appName, version),
)

// Использование
resp, err := client.Do(req)
```

Метрики клиента: `app_http_client_requests_total`, `app_http_client_requests_inflight`, `app_http_client_responses_duration_seconds_*` по caller/origin.

### Pprof (Debug)

```go
import "github.com/vmkteam/appkit/pprof"

func (a *App) registerDebugHandlers() {
    pprof.Register(a.echo) // /debug/pprof/*
}
```

Endpoints: `/debug/pprof/`, `/debug/pprof/heap`, `/debug/pprof/goroutine`, `/debug/pprof/profile?seconds=30`.

### X-Request-ID

```go
import "github.com/vmkteam/appkit/xrid"

// Middleware: генерирует/валидирует/пропускает X-Request-ID
a.echo.Any("/v1/rpc/", echo.WrapHandler(appkit.XRequestID(a.srv)))

// Получить из контекста
requestID := xrid.FromContext(ctx)
```

### VCS Version

Автоматическое извлечение версии из Git (go build -ldflags или VCS info):

```go
import "github.com/vmkteam/appkit/vcs"

version := vcs.Version() // git commit hash
```

### Real IP

Определение реального IP клиента с поддержкой trust CIDR ranges:

```go
import "github.com/vmkteam/appkit/realip"

// Настройка trusted proxies
a.echo.IPExtractor = realip.Extractor(trustedCIDRs)
```

### Route Listing

Автоматический HTML-список всех маршрутов (полезно в dev-режиме):

```go
// GET / — список всех зарегистрированных маршрутов
appkit.RegisterRouteList(a.echo)
```

### Context Utilities

```go
import "github.com/vmkteam/appkit/appctx"

// Хранение и получение метаданных запроса из контекста
ip := appctx.IP(ctx)
ua := appctx.UserAgent(ctx)
platform := appctx.Platform(ctx)
version := appctx.Version(ctx)
country := appctx.Country(ctx)
```

## Echo handlers (типичная структура)

```go
// pkg/app/handlers.go
func (a *App) registerHandlers() {
    a.echo.Use(middleware.CORSWithConfig(middleware.CORSConfig{
        AllowOrigins: []string{"*"},
    }))
    a.echo.GET("/status", a.statusHandler)
}

func (a *App) registerAPIHandlers() {
    a.srv = rpc.New(a.db, a.Logger, a.cfg.Server.IsDevel)
    a.echo.Any("/v1/rpc/*", echo.WrapHandler(appkit.XRequestID(a.srv)))
    a.echo.GET("/v1/rpc/doc/*", echo.WrapHandler(smdbox.NewHandler(a.srv)))
}
```
