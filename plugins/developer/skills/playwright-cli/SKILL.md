---
name: playwright-cli
description: "playwright-cli — Browser Automation. Accessibility tree snapshots, element interaction, network monitoring, screenshots."
---

# playwright-cli — Browser Automation

Binary: `/opt/homebrew/bin/playwright-cli` (v0.1.5+, Homebrew)
Source: microsoft/playwright-mcp — CLI operates on accessibility tree (snapshots), not screenshots.

## Workflow

1. `playwright-cli open <url>` — open browser (headless by default, `--headed` for visible)
2. `playwright-cli snapshot` — get accessibility tree with element refs (`e15`, `e21`, ...)
3. Interact using refs: `click e15`, `fill e12 "text"`, `type "text"`, `press Enter`
4. `playwright-cli snapshot` — verify result after each action
5. `playwright-cli close` — done

## Sessions

Use `-s=<name>` for isolated sessions: `playwright-cli -s=myapp open https://example.com`
All subsequent commands must use the same session flag: `playwright-cli -s=myapp snapshot`

## Commands Reference

### Core
```
open [url]                  # open browser. Options: --headed, --browser=chrome|firefox|webkit|msedge, --persistent, --profile=<path>
attach [name]               # attach to running browser. Options: --cdp <endpoint>, --endpoint <pw-server>, --extension
close                       # close browser page
goto <url>                  # navigate to URL
snapshot [element]          # capture accessibility tree. Options: --depth=N (limit depth), --filename=file.yml
click <target> [button]     # click element. button: left(default)|right. Options: --modifiers=Shift|Control
dblclick <target> [button]  # double-click. Options: --modifiers
fill <target> <text>        # set input value directly (fast). Options: --submit (press Enter after)
type <text>                 # type into focused element (keystrokes). Options: --submit
select <target> <val>       # select dropdown option
check <target>              # check checkbox/radio
uncheck <target>            # uncheck checkbox/radio
hover <target>              # hover over element
drag <start> <end>          # drag and drop
upload <file>               # upload file(s)
eval <func> [element]       # run JS. Example: eval "() => document.title". Options: --filename=script.js
dialog-accept [prompt]      # accept alert/confirm/prompt dialog
dialog-dismiss              # dismiss dialog
resize <w> <h>              # resize viewport
delete-data                 # delete session data
```

### Navigation
```
go-back / go-forward / reload
```

### Keyboard
```
press <key>          # Enter, Tab, ArrowLeft, Control+a, Shift+Tab, etc.
keydown <key>        # hold key
keyup <key>          # release key
```

### Mouse (low-level)
```
mousemove <x> <y>    # move to coordinates
mousedown [button]   # press button (left|right)
mouseup [button]     # release
mousewheel <dx> <dy> # scroll. Down: 0 -300, Up: 0 300
```

### Screenshot & PDF
```
screenshot [target]  # viewport screenshot. Options: --full-page, --filename=file.png
pdf                  # save as PDF. Options: --filename=file.pdf
```

### Tabs
```
tab-list             # list tabs
tab-new [url]        # new tab
tab-close [index]    # close tab
tab-select <index>   # switch tab
```

### Storage
```
state-save [file]    # save cookies + localStorage to file
state-load <file>    # restore state from file

cookie-list          # Options: --domain=, --path=
cookie-get <name>
cookie-set <name> <value>  # Options: --domain, --path, --expires, --httpOnly, --secure, --sameSite
cookie-delete <name>
cookie-clear

localstorage-list / localstorage-get <key> / localstorage-set <key> <value> / localstorage-delete <key> / localstorage-clear
sessionstorage-list / sessionstorage-get <key> / sessionstorage-set <key> <value> / sessionstorage-delete <key> / sessionstorage-clear
```

### Network
```
route <pattern>            # mock requests. Options: --status=200, --body='{}', --content-type=application/json, --header="name: value"
route-list                 # list active mocks
unroute [pattern]          # remove mocks
network-state-set offline|online
network                    # list requests. Options: --static, --request-body, --request-headers, --filter="/api/.*", --clear
```

### DevTools
```
console [min-level]   # info(default)|error|warning|debug. --clear
run-code [code]       # run Playwright code: "(page) => page.evaluate(...)". --filename=file.js
tracing-start / tracing-stop
video-start [file] / video-stop / video-chapter <title>
show                  # live dashboard with screencasts
```

### Session Management
```
list                 # list sessions. --all for all workspaces
close-all            # close all browsers
kill-all             # force-kill zombie processes
```

## Element Targeting (priority order)

1. **Snapshot refs** (preferred): `e15`, `e21` — from `snapshot` output
2. **CSS selectors**: `"#main > button"`, `".form input[type=email]"`
3. **Playwright locators**: `"getByRole('button', { name: 'Submit' })"`, `"getByTestId('id')"`, `"getByText('Click')"`

## Rules

- ALWAYS run `snapshot` before interacting — refs change after each page mutation
- Use `fill` over `type` when targeting a specific element (faster, more reliable)
- Use `--submit` flag on `fill`/`type` to press Enter (saves an extra `press Enter` call)
- Use `--depth=N` on `snapshot` for large pages to reduce output
- Use `--raw` when piping output to other tools
- Use `--headed` for debugging, headless for automation
- Use `state-save`/`state-load` for auth flows — login once, reuse state
- Use `screenshot` after actions to verify visual result when snapshot is insufficient
- Parse snapshot YAML to find element refs — look for `- e<N>` patterns

## Environment Variables

Key variables (prefix `PLAYWRIGHT_MCP_`):
- `PLAYWRIGHT_CLI_SESSION` — default session name
- `PLAYWRIGHT_MCP_BROWSER` — chrome|firefox|webkit|msedge
- `PLAYWRIGHT_MCP_HEADLESS` — headless mode
- `PLAYWRIGHT_MCP_VIEWPORT_SIZE` — e.g. "1280x720"
- `PLAYWRIGHT_MCP_USER_AGENT` — custom UA
- `PLAYWRIGHT_MCP_TIMEOUT_ACTION` — action timeout ms (default 5000)
- `PLAYWRIGHT_MCP_TIMEOUT_NAVIGATION` — navigation timeout ms (default 60000)
