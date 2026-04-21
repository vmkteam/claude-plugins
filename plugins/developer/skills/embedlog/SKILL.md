---
name: embedlog
description: "Embedlog — встраиваемое structured-логирование с Prometheus-метриками. Используй при подключении логгера в новую структуру (embedlog.Logger), добавлении полей в лог или настройке уровней."
---

# Embedlog

- Upstream: https://github.com/vmkteam/embedlog
- Библиотека логирования для встраивания в структуры через `embedlog.Logger`
- Dual-level: info → stdout, error → stderr (автосплит)
- JSON (prod) / text-цветной (dev, `NewDevLogger`); source location авто

## Встраивание

```go
type MyService struct {
    embedlog.Logger
    repo db.EntityRepo
}

func (s *MyService) Process(ctx context.Context) error {
    s.Print("processing started")
    if err != nil {
        s.Error("processing failed", "err", err)
        return err
    }
    s.Print("processing completed", "count", count)
    return nil
}
```

## Init

```go
logger := embedlog.NewLogger(os.Stdout, os.Stderr, true) // json=true, prod
logger := embedlog.NewDevLogger()                         // text+colors, dev
```

## API

- `logger.Print(msg, args...)` — info → stdout
- `logger.Error(msg, args...)` — error → stderr
- `logger.PrintOrErr(err, msg)` — `err != nil` ? Error : Print

Всегда structured args (`"key", val`), не конкатенация.

## Метрики

`app_log_events_total{type="info"|"error"}` — counter (алерты на error rate).

## Интеграции

```go
// zenrpc-middleware
rpc.Use(
    zm.WithSLog(logger.Print, zm.DefaultServerName, nil),
    zm.WithErrorSLog(logger.Error, zm.DefaultServerName, nil),
)

// go-pg SQL logging (dblog.go)
zm.WithSQLLogger(dbo.DB, isDevel, allowDebugFn(), allowDebugFn())
```
