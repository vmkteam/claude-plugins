# /solve — проверка API-контракта на локальном сервере

Нужна, когда менялся API-контракт: новые JSON-поля, изменённые структуры ответов, новые методы. Для внутренней логики и рефакторинга без изменения API — не нужна.

1. Запусти собранный на VERIFY бинарник в фоне и запомни PID: `./{NAME} -config=cfg/local.toml -dev & echo $! > /tmp/{TASK_ID}-server.pid` (`{NAME}` — из Makefile). Не `make run`: он запускает сервер через `go run` отдельным процессом, и PID будет не его.
2. Если метод требует авторизации — возьми credentials из локальной БД:
   ```bash
   psql -d {database} -c 'SELECT "{auth_key_field}" FROM "{users_table}" WHERE {condition} LIMIT 1;'
   ```
3. Вызови затронутый метод:
   ```bash
   curl -s http://localhost:{port}/{rpc_endpoint} \
     -H "Content-Type: application/json" \
     -H "{auth_header}: {auth_value}" \
     -d '{"jsonrpc":"2.0","method":"{method}","params":{...},"id":1}'
   ```
4. Убедись, что новое поле есть в ответе и содержит корректные данные.
5. Останови сервер по сохранённому PID: `kill $(cat /tmp/{TASK_ID}-server.pid)`. Не используй `pkill -f`: шаблон совпадёт с командной строкой собственного shell агента и убьёт его.

Порт, endpoint, заголовок авторизации и таблица пользователей — из project-index и `cfg/local.toml`.
