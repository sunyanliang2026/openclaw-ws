# Adoption Plan (Current OpenClaw)

## 0. Baseline (already observed)

- Gateway is healthy and managed by systemd.
- One cron job exists but has repeated timeout failures.
- No standardized local orchestration assets (task schema/routing/concurrency policy).

## 1. Stabilize scheduler first

- Reduce high-frequency cron turns for status reports.
- Increase timeout budget for report jobs.
- Prefer deterministic monitor scripts before model-driven summary turns.

## 2. Standardize orchestration artifacts

- Use `config/task-schema.example.json` as the base for every task.
- Route work by `config/agent-selection.json` instead of ad-hoc model choice.
- Enforce `config/concurrency.json` limits when launching parallel tasks.

## 3. Add failure-aware retries

- For every failed attempt:
  - store reason in `lastFailure.reason`
  - generate corrected prompt from prior failure (`scripts/adjust-prompt.sh`)
  - retry with bounded attempts (`maxAttempts`)
- Current runtime retry policy: automatic relaunch with backoff `30s -> 120s -> 300s`.
- Move exhausted tasks to failed state with explicit reason.
- Retries are routed by `failureClass` via `config/failure-policies.json`:
  - `infra`, `code`, `rate_limit` can retry with class-specific backoff/limits
  - `ci`, `auth` are non-retryable by default

## 3.1 Enforce launch concurrency

- `scripts/start-task.sh` now reads `config/concurrency.json`.
- If active tmux sessions reach `limits.maxConcurrentAgents`, task is marked `queued` with `queueReason=concurrency_limit` instead of forcing launch.
- Reconcile/cron cycle can retry launch later without crashing the scheduler.

## 3.2 Non-blocking retries and SLA timeouts

- Reconcile no longer sleeps during backoff.
- On failure it writes `nextRetryAtEpoch`; retries are executed on later scheduler turns.
- Add per-task SLA fields:
  - `maxRunMinutes` -> fail with `run_timeout`.
  - `maxQueueMinutes` -> fail with `queue_timeout`.

## 4. Operate with deterministic checks first

- Check:
  - `tmux` session alive
  - branch/PR existence
  - CI status
- Only call an LLM when deterministic checks cannot decide next action.

## 4.1 PR quality gates

- `pr-check.sh` enforces configurable gates from `config/quality-gates.json`.
- If required PR sections or task verification fields are missing, task status becomes `needs_update`.
- Mergeability checks are enforced (`requireMergeable`) and branch lag vs base can be capped (`maxBehindCommits`).

## 4.2 Structured event logs

- Reconcile/PR-check/start-task emit JSONL event logs under `runtime/events`.
- Use events for metrics dashboards and alert conditions (timeouts, retry churn, CI failure spikes).

## 4.3 Metrics and alert checks

- Use `scripts/metrics-report.sh` for rolling window health metrics.
- Use `scripts/alert-check.sh` with thresholds from `config/alerts.json`.
- Schedule alert checks hourly to surface regressions without manual log review.
- Enable optional webhook notifications (Feishu/Slack/generic) with cooldown-based dedupe.

## 5. Rollout sequence for this machine

1. Keep current cron change for lower noise and fewer timeouts.
2. Make `openclaw-optimizer` configs your source of truth.
3. Install cron via `scripts/install-cron.sh` to invoke reconciliation every 10 minutes.
4. Put active tasks in `runtime/tasks/active/*.json` using the provided schema.
5. Use `scripts/start-task.sh <task_id>` to launch tasks consistently.
6. Let `scripts/pr-check.sh` track PR/CI and move terminal tasks to completed/failed.
7. Use `scripts/stop-task.sh` for controlled shutdown/archive and optional worktree cleanup.
8. Gradually migrate active flows to the new task schema.
9. Install cron via `scripts/install-cron.sh` to include orphan worktree cleanup (`cleanup-worktrees.sh`) every hour.
