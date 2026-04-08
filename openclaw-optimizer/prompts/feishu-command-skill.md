# Feishu Command Dispatch Skill

When a Feishu message starts with `/newtask`, dispatch it to local task scripts.

## Steps

1. Preserve the raw message text.
2. Call:

```bash
/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/feishu-command-dispatch.sh --text '<raw_message>'
```

3. Read JSON output and reply in chat with:
- `taskId`
- `project`
- `started`
- brief next action
- On failure, prefer `replyText`; include `code` only when user asks for technical detail.

## Command schema

```text
/newtask
title: ...
project: internal-openclaw
type: backend-feature|frontend-feature|bug-fix|docs-changelog
priority: high|medium|low
start: true|false
prompt: ...
```

Notes:
- `prompt` can be multiline (remaining lines are appended).
- If `id` is omitted, dispatcher auto-generates task id.
- Dispatcher emits standard failure JSON with `code/message/detail/hint/replyText`.
