# Feishu Command Skill

Purpose: keep Feishu websocket as the primary demand entry and convert chat commands into local tasks.

## Command

Use this in Feishu chat:

```text
/newtask
title: Build marketing website v1
project: internal-openclaw
type: frontend-feature
priority: high
start: true
prompt: Build a responsive website with home, pricing, and contact pages. Add basic tests.
```

## Dispatcher

Script: `scripts/feishu-command-dispatch.sh`

Examples:

```bash
./scripts/feishu-command-dispatch.sh --text $'/newtask\ntitle: Build site\nproject: internal-openclaw\ntype: frontend-feature\npriority: high\nprompt: Build pages and tests.'
```

```bash
./scripts/feishu-command-dispatch.sh --file /tmp/feishu-message.txt
```

## Behavior

- Parses `/newtask` message text.
- Calls `scripts/new-task.sh`.
- Calls `scripts/start-task.sh` when `start=true` (default from `config/inbound-feishu.json.autoStart`).
- Writes events to `runtime/events/feishu-command-events-YYYYMMDD.jsonl`.

## Standard reply text on parse/dispatch failure

The dispatcher always returns JSON on both success and failure.
Failure shape:

```json
{
  "ok": false,
  "code": "unsupported_command|config_parse_error|task_create_failed|task_start_failed",
  "message": "...",
  "detail": "...",
  "hint": "...",
  "example": "/newtask | title: ... | project: internal-openclaw | type: backend-feature | priority: medium | start: true | prompt: ...",
  "replyText": "Task dispatch failed: [code] message. hint"
}
```

Success shape includes:
- `ok=true`
- `taskId`
- `started`
- `replyText` (chat-safe one-line receipt)

## Notes

- Keep `config/inbound-feishu.json.enabled=false` for normal operations.
- Use HTTP inbound only as a debug fallback when a public callback endpoint is required.
