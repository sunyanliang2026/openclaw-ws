# OpenClaw + GBrain Integration

This workspace now uses a split model:

- `openclaw-optimizer/runtime/` keeps raw execution state.
- `~/brain/` keeps reusable knowledge for lookup.

That boundary matters. Do not dump full `run.log` files into the brain.

## Recommended data flow

### 1. Task flow

Feishu `/newtask` -> `feishu-command-dispatch.sh` -> `new-task.sh` -> `start-task.sh` -> Codex/OpenClaw runtime -> `write-task-summary.sh` -> `sync-task-summary-to-brain.sh` -> `~/brain/projects/openclaw-tasks/*.md`

What goes into the brain:

- task metadata
- task status and timestamps
- branch, repo, worktree
- verification evidence
- run log path
- failure reason and failure class
- short run log excerpt only when there is failure-like signal

What stays in runtime only:

- full `run.log`
- tmux state
- retry bookkeeping
- queue and scheduler noise

### 2. Feishu normal Q&A

Do not store every raw message.

Default path: normal Feishu turns handled by the live OpenClaw gateway now auto-capture after the final reply is delivered.

What happens automatically:

- `/newtask` stays on the dispatcher path
- normal turns still route through the existing Feishu agent flow
- after the final reply is sent, the gateway asynchronously calls `capture-feishu-turn-to-brain.sh`
- the capture script still decides whether to skip or write a note based on durable-signal rules

Manual path: use the wrapper when you want to simulate a turn locally, test capture behavior, or drive Feishu from the shell.

Wrapper:

`[feishu-turn-wrapper.sh](/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/feishu-turn-wrapper.sh)`

Example:

```bash
/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/feishu-turn-wrapper.sh \
  --chat-id oc_dccaa7d10c8a1453d3b4656f792666d8 \
  --message "以后所有 5xx 响应都保留 request id。" \
  --capture-summary "Decision: all 5xx responses should preserve request id for support tracing." \
  --durable-type decision \
  --json
```

What it does:

- `/newtask` routes to the dispatcher and sends `replyText` back to Feishu
- normal turns call `openclaw agent --json` on the matching Feishu session
- sends the reply back with `openclaw message send`
- runs `capture-feishu-turn-to-brain.sh` after the reply, which mirrors the same capture logic now wired into the live gateway path

Use `capture-feishu-turn-to-brain.sh` after replying when the exchange contains durable signal:

- a decision
- a new fact
- a standing preference or rule
- a follow-up item worth retrieving later

Default filing path: `~/brain/inbox/feishu/`

Script:

`[capture-feishu-turn-to-brain.sh](/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/capture-feishu-turn-to-brain.sh)`

Example:

```bash
/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/capture-feishu-turn-to-brain.sh \
  --message "以后所有 5xx 响应都保留 request id" \
  --reply "收到，后续我会把 request id 作为 5xx 响应的固定字段保留。" \
  --summary "Decision: all 5xx responses should preserve request id for support tracing." \
  --chat-id oc_xxx \
  --project internal-openclaw \
  --durable-type decision
```

Notes:

- The script skips `/newtask`, heartbeat traffic, acknowledgements, and empty turns by default.
- The live gateway now uses this script automatically for ordinary Feishu turns after reply delivery.
- It writes a curated summary, not the full transcript.
- If an OpenClaw upgrade replaces the installed `monitor-*.js`, reapply the live patch with `[apply-feishu-brain-capture-patch.sh](/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/apply-feishu-brain-capture-patch.sh) --apply --restart`.

### 3. Direct Codex CLI sessions

Do not save full terminal transcripts by default.

Preferred path for non-interactive runs: use `codex-brain-exec.sh`.

Capture only the session closeout:

- what changed
- what conclusion was reached
- repo or branch involved
- risk or follow-up

Default filing path: `~/brain/inbox/codex-cli/`

Wrapper:

`[codex-brain-exec.sh](/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/codex-brain-exec.sh)`

Example:

```bash
/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/codex-brain-exec.sh \
  --title "登录接口 500 修复" \
  --project internal-openclaw \
  -- \
  codex exec -C /home/ubuntu/.openclaw/workspace "修复登录接口 500，并说明验证结果。"
```

Notes:

- The wrapper is intentionally limited to `codex exec`.
- It captures the final message via `codex exec -o ...`, stores console output under `runtime/codex-cli-runs/`, and writes only the closeout into the brain.
- On this host, sandboxed `codex exec` may warn or fail on `bubblewrap`. When you already trust the workspace boundary, pass the same flags you use in task runs, for example `--dangerously-bypass-approvals-and-sandbox`.
- For interactive `codex` TUI sessions, continue using `capture-brain-note.sh` manually after the session.

## Scripts

### Task summary sync

`[sync-task-summary-to-brain.sh](/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/sync-task-summary-to-brain.sh)`

Examples:

```bash
/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/sync-task-summary-to-brain.sh --all
/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/sync-task-summary-to-brain.sh \
  --summary-file /home/ubuntu/.openclaw/workspace/openclaw-optimizer/runtime/summaries/req-20260412-032043-.json
```

Notes:

- `write-task-summary.sh` now calls this automatically after summary generation.
- Import target is `~/brain/projects/openclaw-tasks/`.
- Import is `--no-embed`; run `gbrain embed --stale` later once embeddings are configured.

### Generic note capture

`[capture-brain-note.sh](/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/capture-brain-note.sh)`

Examples:

```bash
/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/capture-brain-note.sh \
  --source feishu \
  --title "老板要求登录接口错误要保留 request id" \
  --body "Decision: keep request id in all 5xx responses for support tracing." \
  --project internal-openclaw
```

```bash
/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/capture-brain-note.sh \
  --source codex-cli \
  --title "登录页 500 修复会话摘要" \
  --body-file /tmp/session-summary.md \
  --project internal-openclaw \
  --task-id req-20260412-999999-demo
```

## Retrieval discipline

Follow this order when handling a new request:

1. `gbrain search` / `gbrain query`
2. agent memory / workspace rules
3. runtime logs and task state
4. external APIs or web search

For a local hard-enforced entrypoint, use:

`[brain-first-agent.sh](/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/brain-first-agent.sh)`

Example:

```bash
/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/brain-first-agent.sh \
  --message "What did we decide about Feishu auto-capture?" \
  --json
```

What it does:

- runs `gbrain ask` first
- runs `gbrain search` second
- injects both results into the agent prompt
- then calls `openclaw agent`

## Operational notes

- Current brain path: `/home/ubuntu/brain`
- Current task sync target: `/home/ubuntu/brain/projects/openclaw-tasks`
- Current Q&A capture targets: `/home/ubuntu/brain/inbox/feishu` and `/home/ubuntu/brain/inbox/codex-cli`
- No embedding API keys are configured yet, so search is keyword-first today

## Local Codex bundle path

If ClawHub does not expose `gbrain` skills/plugin, use the local Codex bundle wrapper:

- Bundle root: `/home/ubuntu/.openclaw/workspace/openclaw-optimizer/plugins/gbrain-codex-bundle`
- Includes: upstream gbrain skills (copied under `skills/`) + bundled MCP server `gbrain_bundle`

Install or refresh:

```bash
openclaw plugins install /home/ubuntu/.openclaw/workspace/openclaw-optimizer/plugins/gbrain-codex-bundle --force
openclaw gateway restart
```

Verify:

```bash
openclaw plugins inspect gbrain-codex-bundle --json
openclaw agent --agent main --message "List tool names that start with gbrain_bundle__ only." --json
```

Notes:

- This path does not replace the existing `mcp.servers.gbrain` entry; it adds bundle-backed MCP tools with the `gbrain_bundle__` prefix.
- `openclaw plugins` may print a warning about `plugins.allow` being empty when non-bundled plugins are discovered. This is advisory, not a runtime failure.
