---
name: embedlog
description: "Embedlog — встраиваемое логирование для Go с Prometheus метриками и structured logging."
---

# Embedlog — встраиваемое логирование

embedlog (https://github.com/vmkteam/embedlog) — библиотека логирования для Go, предназначенная для встраивания в структуры приложения.

## Ключевые возможности

- **Dual-level logging** — stdout (info) и stderr (errors) автоматически разделяются
- **JSON и text форматы** — JSON для production, text для разработки
- **Print/Error API** — простой интерфейс с поддержкой context
- **Embeddable design** — встраивается в структуры через `embedlog.Logger`
- **Prometheus метрики** — `app_log_events_total` (info/error)
- **Source location** — автоматическое логирование файла/строки
- **NewDevLogger** — цветное логирование для dev-окружения

## Использование

### Встраивание в структуры

```go
type MyService struct {
    embedlog.Logger
    repo db.EntityRepo
}

func NewMyService(logger embedlog.Logger, repo db.EntityRepo) *MyService {
    return &MyService{
        Logger: logger,
        repo:   repo,
    }
}

// Использование
func (s *MyService) Process(ctx context.Context) error {
    s.Print("processing started")
    // ...
    if err != nil {
        s.Error("processing failed", "err", err)
        return err
    }
    s.Print("processing completed", "count", count)
    return nil
}
```

### Инициализация

```go
// Production (JSON)
logger := embedlog.NewLogger(os.Stdout, os.Stderr, true) // json=true

// Development (text, цветной)
logger := embedlog.NewDevLogger()
```

### API

```go
logger.Print(msg string, args ...any)     // info → stdout
logger.Error(msg string, args ...any)     // error → stderr
logger.PrintOrErr(err error, msg string)  // если err != nil → Error, иначе Print
```

## Prometheus метрики

Автоматически экспортируются:

| Метрика | Labels | Описание |
|---------|--------|----------|
| `app_log_events_total` | `type="info"` | Количество info-логов |
| `app_log_events_total` | `type="error"` | Количество error-логов |

Полезно для алертов на рост error rate.

## Интеграция с zenrpc-middleware

```go
rpc.Use(
    zm.WithSLog(logger.Print, zm.DefaultServerName, nil),
    zm.WithErrorSLog(logger.Error, zm.DefaultServerName, nil),
)
```

## Интеграция с go-pg (SQL logging)

```go
// dblog.go — логирование SQL-запросов
zm.WithSQLLogger(dbo.DB, isDevel, allowDebugFn(), allowDebugFn())
```

## Рекомендации

- Production: JSON формат, мониторинг `app_log_events_total{type="error"}`
- CLI: text формат с verbose флагом
- Structured args: `s.Print("order created", "orderId", id, "total", total)` — не конкатенация строк
