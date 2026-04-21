---
name: appkit
description: "Appkit — библиотека vmkteam/appkit: метрики, pprof, HTTP client, service metadata, X-Request-ID. Используй при подключении метрик/pprof в сервис, работе с HTTP-клиентом appkit или добавлении корреляционных ID."
---

# Appkit

- Upstream: https://github.com/vmkteam/appkit
- Связанные: /embedlog, /cron, /prometheus (PromQL к `app_*` метрикам)

## Метрики (`appkit/metrics`)

`metrics.Register(a.echo)` — экспонирует `/metrics`.

Server: `app_http_requests_total` (labels: job, code, method, uri, server), `app_http_responses_duration_seconds_*`.

Client: `app_http_client_requests_total`, `app_http_client_requests_inflight`, `app_http_client_responses_duration_seconds_*` (labels: caller, origin).

Metadata: `app_metadata_service` (version, deps), `app_metadata_services` (sync/async/external links), `app_metadata_db_connections_total`, `app_log_events_total`.

## Service Metadata (`appkit/metadata`)

Декларация зависимостей — используется /onboard и /investigate для auto-discovery топологии:

```go
md := metadata.New(a.appName, version)
md.AddDatabase("postgres", a.db.PoolStats)
md.AddService("{dep_service}", metadata.Sync)
md.AddService("{async_service}", metadata.Async)
md.AddService("{ext_service}", metadata.External)
md.Register()
```

## HTTP Client (`appkit/httpclient`)

Исходящие запросы с авто-метриками и internal headers:

```go
client := httpclient.New(
    httpclient.WithMetrics("caller-service"),
    httpclient.WithInternalHeaders(appName, version),
)
```

## Pprof (`appkit/pprof`)

`pprof.Register(a.echo)` → `/debug/pprof/{,heap,goroutine,profile?seconds=30}`.

## X-Request-ID (`appkit/xrid`)

Генерация/валидация/прокидывание X-Request-ID. Обёртка для RPC handler: `appkit.XRequestID(a.srv)`. В коде: `xrid.FromContext(ctx)`.

## VCS Version (`appkit/vcs`)

`vcs.Version()` — git commit hash из `go build -ldflags` или VCS info.

## Real IP (`appkit/realip`)

`a.echo.IPExtractor = realip.Extractor(trustedCIDRs)` — учёт trust CIDR.

## Route Listing

`appkit.RegisterRouteList(a.echo)` — HTML-список маршрутов на `GET /` (dev).

## Context (`appkit/appctx`)

`appctx.{IP, UserAgent, Platform, Version, Country}(ctx)` — метаданные запроса.

## Канонические handlers (echo)

```go
func (a *App) registerHandlers() {
    a.echo.Use(middleware.CORSWithConfig(middleware.CORSConfig{AllowOrigins: []string{"*"}}))
    a.echo.GET("/status", a.statusHandler)
}

func (a *App) registerAPIHandlers() {
    a.srv = rpc.New(a.db, a.Logger, a.cfg.Server.IsDevel)
    a.echo.Any("/v1/rpc/*", echo.WrapHandler(appkit.XRequestID(a.srv)))
    a.echo.GET("/v1/rpc/doc/*", echo.WrapHandler(smdbox.NewHandler(a.srv)))
}
```
