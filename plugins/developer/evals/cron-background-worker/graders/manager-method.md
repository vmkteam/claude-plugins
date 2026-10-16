---
type: llm
---

PASS if the job is a method of the domain manager with signature func(ctx context.Context) error, registered in a vmkteam/cron Manager built in the app layer (newCron in pkg/app) with the schedule taken from config (CronConfig / TOML) rather than hardcoded.
FAIL if the main recommendation is a separate worker/cron package inside the domain, a custom generic Job wrapper over vmkteam/cron, or a hand-rolled goroutine with time.Ticker.
