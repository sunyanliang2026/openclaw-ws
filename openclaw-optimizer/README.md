# OpenClaw Optimizer

This folder distills practical ideas from `OpenClaw + Claude Code .pdf` into a minimal, reusable setup for the current machine.

## What is included

- `config/agent-selection.json`: route tasks to the right model/agent.
- `config/agents/*.json`: agent profile catalog (launch command + capabilities).
- `config/skills/registry.json`: reusable skill registry for orchestration.
- `config/concurrency.json`: guardrails to avoid RAM spikes and thrashing.
- `config/task-schema.example.json`: a normalized task record format.
- `config/quality-gates.json`: PR quality gate rules (`needs_update` when unmet).
- `config/alerts.json`: threshold config for automated alert checks.
- `config/failure-policies.json`: failure-class retry routing policy.
- `prompts/backend-feature-with-client-context.md`: a high-signal task prompt template.
- `scripts/reconcile-tasks.sh`: deterministic monitor loop for task state updates.
- `scripts/new-project.sh`: scaffold a new project manifest.
- `scripts/new-task.sh`: scaffold a new task from project + requirement context.
- `scripts/archive-task.sh`: move finished or discarded tasks into a durable archive with reason metadata.
- `scripts/feishu-command-dispatch.sh`: parse `/newtask` commands from Feishu chat and dispatch task creation/start.
- `scripts/validate-manifests.sh`: validate agent/skill/project/routing consistency.
- `scripts/feishu-inbound-server.py`: receive Feishu demand messages and create tasks.
- `scripts/feishu-inbound.sh`: start/stop/status wrapper for Feishu inbound server.
- `scripts/adjust-prompt.sh`: retry-time prompt adjustment based on failure reason.
- `scripts/cleanup-worktrees.sh`: hourly orphan worktree cleanup with tmux safety checks.
- `scripts/cleanup-archives.sh`: retention-based cleanup for archived tasks and stale run artifacts.
- `scripts/lifecycle-audit.sh`: audit task lifecycle health and optionally auto-archive stale `ready_for_review` tasks.
- `scripts/healthcheck.sh`: single-command machine/operator health check (auth, gateway, Feishu, ports, memory/swap, git).
- `scripts/session-check.sh`: verify task/session consistency and optionally fix stale tmux bindings.
- `scripts/session-manage.sh`: tmux session list/attach/orphan cleanup for operator use.
- `scripts/github-task-overview.sh`: one-command PR/checks/mergeability view for active tasks.
- `scripts/verify-runtime-boundary.sh`: enforce runtime-vs-repo boundary by validating `.gitignore` and tracked files.
- `scripts/write-task-summary.sh`: generate/update a normalized task summary artifact in `runtime/summaries/`.
- `scripts/notify-task-completion.sh`: send completed-task summary back to Feishu (or configured channel target).
- `scripts/metrics-report.sh`: rolling metrics report from JSONL runtime events.
- `scripts/alert-check.sh`: threshold-based alert checker using metrics report.
- `docs/adoption-plan.md`: step-by-step rollout plan for your current OpenClaw.
- `docs/structure-upgrade.md`: scaling layout for new agent/skill/project/demand onboarding.
- `docs/feishu-command-skill.md`: lightweight websocket command dispatch workflow.
- `TODO.md`: prioritized roadmap for making this OpenClaw setup production-stable on this machine.

## Structure for scaling

- `projects/*.json`: one file per project/repo (defaults, constraints, skills).
- `config/agents/*.json`: add/replace agent runtime behavior without editing scheduler scripts.
- `config/skills/registry.json`: keep skill metadata decoupled from task instances.
- `templates/project.example.json`: manifest template for new projects.
- `templates/requirement.example.md`: requirement brief template for new demands.

## Bootstrap a new project and task

Create a project manifest:

```bash
/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/new-project.sh \
  --id my-project \
  --name "My Project" \
  --repo /abs/path/to/repo
```

Create a task:

```bash
/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/new-task.sh \
  --project my-project \
  --task-id feat-my-first-task \
  --title "Implement API hardening for /detect/text"
```

Launch it:

```bash
/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/start-task.sh feat-my-first-task
```

Validate manifests:

```bash
/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/validate-manifests.sh
```

Feishu websocket command dispatch (recommended):

```bash
# Parse /newtask message text and create/start task
/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/feishu-command-dispatch.sh --text $'/newtask\ntitle: Build website v1\nproject: internal-openclaw\ntype: frontend-feature\npriority: high\nnotify: true\nnotify_channel: feishu\nnotify_account: main\nnotify_to: chat:oc_xxx\nprompt: Build pages and tests.'
```

`/newtask` supports optional completion callback keys:

- `notify: true|false`
- `notify_channel: feishu`
- `notify_account: main`
- `notify_to: chat:<chatId> | user:<openId>`

Feishu inbound HTTP bridge (fallback only):

```bash
# Keep config/inbound-feishu.json enabled=false unless you explicitly need public HTTP callbacks
/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/feishu-inbound.sh status
```

## Why this helps

- Separates orchestration context from execution context.
- Replaces blind retries with reasoned retries.
- Uses deterministic checks first (`tmux`, `git`, `gh`) to reduce token spend.
- Prevents runaway parallelism on limited-memory machines.
- Queues launches when concurrency limit is hit instead of creating more tmux load.

## Quick start

1. Read `docs/adoption-plan.md`.
2. Start by using `task-schema.example.json` for new tasks.
3. Apply `agent-selection.json` and `concurrency.json` in your orchestration flow.
4. Run `scripts/reconcile-tasks.sh` from cron/systemd timer.

## Cron setup

Install the 10-minute reconciliation job (idempotent):

```bash
/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/install-cron.sh
```

Check current cron entries:

```bash
crontab -l
```

Runtime task folders:

- `/home/ubuntu/.openclaw/workspace/openclaw-optimizer/runtime/tasks/active`
- `/home/ubuntu/.openclaw/workspace/openclaw-optimizer/runtime/tasks/completed`
- `/home/ubuntu/.openclaw/workspace/openclaw-optimizer/runtime/tasks/failed`
- `/home/ubuntu/.openclaw/workspace/openclaw-optimizer/runtime/tasks/archived`
- `/home/ubuntu/.openclaw/workspace/openclaw-optimizer/runtime/summaries`

Quality gate states:

- `ready_for_review`: CI and quality gates passed.
- `needs_update`: PR/task metadata failed quality gate checks.
- `ci_failed`: checks failed.

Quality gate can auto-comment on PR when requirements are missing (deduped by issue fingerprint).
PR gate also checks mergeability and branch lag vs base.

Retry behavior:

- `reconcile-tasks.sh` marks retry state and calls `adjust-prompt.sh`.
- Prompt rewrite stores baseline prompt in `launch.basePrompt`.
- Current failure-specific rewrites: `tmux_session_not_alive`, `ci_failed`, default fallback.
- Retry is non-blocking: reconcile writes `nextRetryAtEpoch` and exits; next scheduler turn handles relaunch.
- Retry routing is class-aware (`infra/code/ci/auth/rate_limit/unknown`) and controlled by `config/failure-policies.json`.
- Retry guard is also policy-driven: when `retrying` transitions hit `retryGuard.maxRetryingTransitions`, task is auto-marked `failed` (`reason=retry_exhausted_by_policy`), and optionally auto-archived when `retryGuard.archiveOnTrigger=true`.
- Launch preflight blocks missing agent binaries early (`agent_command_not_found`) to prevent noisy retry loops.

SLA controls (per task JSON):

- `maxRunMinutes`: fail task with `run_timeout` if running too long.
- `maxQueueMinutes`: fail task with `queue_timeout` if pending/queued/retrying too long.

Task launch helper:

```bash
/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/start-task.sh --dry-run <task_id>
/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/start-task.sh <task_id>
```

Default launch mode is non-interactive (`codex exec --full-auto`) to reduce approval stalls in tmux sessions.

Stop task:

```bash
/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/stop-task.sh --keep-worktree --result stopped <task_id>
```

Archive a finished or discarded task:

```bash
/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/archive-task.sh --reason smoke-only <task_id>
```

Generate or refresh task summary manually:

```bash
/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/write-task-summary.sh \
  --task-file /home/ubuntu/.openclaw/workspace/openclaw-optimizer/runtime/tasks/archived/<task_id>.json
```

Run one full cycle manually:

```bash
/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/task-cycle.sh <task_id>
```

Show current task summary:

```bash
/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/task-status.sh
```

Worktree cleanup:

```bash
DRY_RUN=1 /home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/cleanup-worktrees.sh
/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/cleanup-worktrees.sh
```

Archive cleanup (keep last 14 days by default):

```bash
/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/cleanup-archives.sh --dry-run
/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/cleanup-archives.sh --days 14
```

Lifecycle audit (warn or auto-fix stale review tasks):

```bash
/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/lifecycle-audit.sh
/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/lifecycle-audit.sh --fix --review-ttl-hours 72
```

Run a one-shot operator health check:

```bash
/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/healthcheck.sh
```

Check tmux/task session consistency:

```bash
/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/session-check.sh
/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/session-check.sh --fix
```

Session operator helper:

```bash
/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/session-manage.sh list
/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/session-manage.sh kill-orphans
```

GitHub operator overview for active tasks:

```bash
/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/github-task-overview.sh
```

Runtime boundary verification:

```bash
/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/verify-runtime-boundary.sh
```

Structured logs:

- `runtime/events/reconcile-events-YYYYMMDD.jsonl`
- `runtime/events/pr-check-events-YYYYMMDD.jsonl`
- `runtime/events/start-task-events-YYYYMMDD.jsonl`
- `runtime/events/alert-events-YYYYMMDD.jsonl`
- alert notify dedupe state: `runtime/state/alert-state.json`

Metrics and alerts:

```bash
/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/metrics-report.sh
/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/metrics-report.sh --hours 48 --json
/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/alert-check.sh
```

Notification wiring (optional):

- Configure `config/alerts.json.notifications`.
- Or set env vars before cron/manual run:
  - `ALERT_FEISHU_WEBHOOK`
  - `ALERT_SLACK_WEBHOOK`
  - `ALERT_GENERIC_WEBHOOK`
  - `ALERT_GENERIC_BEARER` (optional)
- Alert dedupe uses fingerprint + cooldown (`cooldownMinutes`) to avoid spam.
