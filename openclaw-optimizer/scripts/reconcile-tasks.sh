#!/usr/bin/env bash
set -euo pipefail

# Deterministic task reconciliation loop.
# Checks local execution state first, then updates task state files.

ROOT="${1:-/home/ubuntu/.openclaw/workspace/openclaw-optimizer/runtime}"
ACTIVE_DIR="$ROOT/tasks/active"
COMPLETED_DIR="$ROOT/tasks/completed"
FAILED_DIR="$ROOT/tasks/failed"
LOG_DIR="$ROOT/logs"
LOCK_DIR="$ROOT/locks"
EVENT_DIR="$ROOT/events"
LOCK_FILE="$LOCK_DIR/reconcile.lock"
LOG_FILE="$LOG_DIR/reconcile-$(date +%Y%m%d).log"
EVENT_FILE="$EVENT_DIR/reconcile-events-$(date +%Y%m%d).jsonl"
FAILURE_POLICY_CONFIG="${FAILURE_POLICY_CONFIG:-/home/ubuntu/.openclaw/workspace/openclaw-optimizer/config/failure-policies.json}"

mkdir -p "$ACTIVE_DIR" "$COMPLETED_DIR" "$FAILED_DIR" "$LOG_DIR" "$LOCK_DIR" "$EVENT_DIR"

log() {
  echo "[$(date -Is)] $*" | tee -a "$LOG_FILE"
}

log_event() {
  local event="$1"
  local task_id="${2:-}"
  local status="${3:-}"
  local detail="${4:-}"
  jq -cn \
    --arg ts "$(date -Is)" \
    --arg event "$event" \
    --arg taskId "$task_id" \
    --arg status "$status" \
    --arg detail "$detail" \
    '{ts:$ts,event:$event,taskId:$taskId,status:$status,detail:$detail}' >> "$EVENT_FILE"
}

require_bin() {
  command -v "$1" >/dev/null 2>&1 || {
    log "missing binary: $1"
    exit 1
  }
}

require_bin jq
require_bin tmux
require_bin git
require_bin date
require_bin flock

exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  log "another reconcile run is in progress; skipping"
  log_event "reconcile_skipped_locked" "" "" "lock=$LOCK_FILE"
  exit 0
fi

START_TASK_SCRIPT="/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/start-task.sh"
ADJUST_PROMPT_SCRIPT="/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/adjust-prompt.sh"

classify_failure_class() {
  local reason="$1"
  local status="$2"
  local task_file="$3"
  local prev_class
  prev_class="$(jq -r '.lastFailure.classification // empty' "$task_file")"

  if [[ "$status" == "ci_failed" || "$reason" == "ci_checks_failed" ]]; then
    echo "ci"
    return 0
  fi
  if [[ "$reason" =~ rate_limit|usage_limit|quota ]]; then
    echo "rate_limit"
    return 0
  fi
  if [[ "$reason" =~ auth|oauth|token|credential ]]; then
    echo "auth"
    return 0
  fi
  if [[ "$reason" =~ repo|worktree|branch|git ]]; then
    echo "repo-state"
    return 0
  fi
  if [[ "$reason" =~ pr_closed_not_merged|tests_not_marked_passed|missing_pr_section|missing_task_field ]]; then
    echo "code"
    return 0
  fi
  if [[ "$reason" =~ tmux_session_not_alive|run_timeout|queue_timeout ]]; then
    echo "infra"
    return 0
  fi
  if [[ -n "$prev_class" ]]; then
    echo "$prev_class"
    return 0
  fi
  echo "unknown"
}

policy_retryable() {
  local klass="$1"
  if [[ -f "$FAILURE_POLICY_CONFIG" ]]; then
    jq -r --arg k "$klass" '.classes[$k].retryable // .classes.unknown.retryable // true' "$FAILURE_POLICY_CONFIG"
  else
    echo "true"
  fi
}

policy_max_attempts() {
  local klass="$1"
  local fallback="$2"
  if [[ -f "$FAILURE_POLICY_CONFIG" ]]; then
    jq -r --arg k "$klass" --argjson fb "$fallback" '.classes[$k].maxAttempts // .classes.unknown.maxAttempts // $fb' "$FAILURE_POLICY_CONFIG"
  else
    echo "$fallback"
  fi
}

policy_backoff_seconds_for_attempt() {
  local klass="$1"
  local attempt="$2"
  if [[ -f "$FAILURE_POLICY_CONFIG" ]]; then
    local idx=$((attempt - 1))
    jq -r --arg k "$klass" --argjson i "$idx" '.classes[$k].backoffSeconds[$i] // .classes[$k].backoffSeconds[-1] // .classes.unknown.backoffSeconds[$i] // .classes.unknown.backoffSeconds[-1] // 300' "$FAILURE_POLICY_CONFIG"
  else
    case "$attempt" in
      1) echo 30 ;;
      2) echo 120 ;;
      *) echo 300 ;;
    esac
  fi
}

parse_iso_epoch() {
  local iso="$1"
  if [[ -z "$iso" || "$iso" == "null" ]]; then
    echo ""
    return 0
  fi
  date -d "$iso" +%s 2>/dev/null || echo ""
}

shopt -s nullglob
for task_file in "$ACTIVE_DIR"/*.json; do
  task_id="$(basename "$task_file" .json)"
  failure_reason=""
  now_epoch="$(date +%s)"
  status="$(jq -r '.status // "pending"' "$task_file")"
  max_attempts="$(jq -r '.maxAttempts // 3' "$task_file")"
  attempts="$(jq -r '.attemptCount // 0' "$task_file")"
  tmux_session="$(jq -r '.tmuxSession // empty' "$task_file")"
  max_run_minutes="$(jq -r '.maxRunMinutes // 0' "$task_file")"
  max_queue_minutes="$(jq -r '.maxQueueMinutes // 0' "$task_file")"
  started_at="$(jq -r '.startedAt // empty' "$task_file")"
  queued_at="$(jq -r '.queuedAt // empty' "$task_file")"
  created_at="$(jq -r '.createdAt // empty' "$task_file")"
  next_retry_at_epoch="$(jq -r '.nextRetryAtEpoch // empty' "$task_file")"
  run_exit_file="$ROOT/task-runs/$task_id/exit.json"

  log "checking task=$task_id status=$status attempts=$attempts/$max_attempts"
  log_event "task_checked" "$task_id" "$status" "attempts=$attempts/$max_attempts"

  if (( max_run_minutes > 0 )) && [[ "$status" == "running" ]]; then
    started_epoch="$(parse_iso_epoch "$started_at")"
    if [[ -n "$started_epoch" ]]; then
      run_age_seconds=$((now_epoch - started_epoch))
      if (( run_age_seconds > max_run_minutes * 60 )); then
        if [[ -n "$tmux_session" ]] && tmux has-session -t "$tmux_session" 2>/dev/null; then
          tmux kill-session -t "$tmux_session" >/dev/null 2>&1 || true
        fi
        tmp="$(mktemp)"
        jq --arg now "$(date -Is)" '.status = "failed" | .updatedAt = $now | .lastFailure.reason = "run_timeout" | .lastFailure.time = $now' "$task_file" > "$tmp"
        mv "$tmp" "$FAILED_DIR/$task_id.json"
        rm -f "$task_file"
        log "task timed out in running state: $task_id"
        log_event "task_failed_timeout" "$task_id" "$status" "failure=run_timeout maxRunMinutes=$max_run_minutes"
        continue
      fi
    fi
  fi

  if (( max_queue_minutes > 0 )) && [[ "$status" == "pending" || "$status" == "queued" || "$status" == "retrying" ]]; then
    queue_base="$queued_at"
    if [[ -z "$queue_base" || "$queue_base" == "null" ]]; then
      queue_base="$created_at"
    fi
    queue_epoch="$(parse_iso_epoch "$queue_base")"
    if [[ -n "$queue_epoch" ]]; then
      queue_age_seconds=$((now_epoch - queue_epoch))
      if (( queue_age_seconds > max_queue_minutes * 60 )); then
        tmp="$(mktemp)"
        jq --arg now "$(date -Is)" '.status = "failed" | .updatedAt = $now | .lastFailure.reason = "queue_timeout" | .lastFailure.time = $now' "$task_file" > "$tmp"
        mv "$tmp" "$FAILED_DIR/$task_id.json"
        rm -f "$task_file"
        log "task timed out in queue state: $task_id"
        log_event "task_failed_timeout" "$task_id" "$status" "failure=queue_timeout maxQueueMinutes=$max_queue_minutes"
        continue
      fi
    fi
  fi

  if [[ "$status" == "retrying" ]] && [[ -n "$next_retry_at_epoch" ]] && [[ "$next_retry_at_epoch" != "null" ]]; then
    if (( now_epoch < next_retry_at_epoch )); then
      log "retry not due yet: $task_id retryAtEpoch=$next_retry_at_epoch now=$now_epoch"
      log_event "retry_waiting" "$task_id" "$status" "retryAtEpoch=$next_retry_at_epoch now=$now_epoch"
      continue
    fi
  fi

  if [[ "$status" == "ready_for_review" || "$status" == "needs_update" || "$status" == "ci_running" || "$status" == "ci_failed" ]]; then
    if [[ -n "$tmux_session" ]]; then
      if tmux has-session -t "$tmux_session" 2>/dev/null; then
        tmux kill-session -t "$tmux_session" >/dev/null 2>&1 || true
        log_event "tmux_killed" "$task_id" "$status" "reason=non_execution_status session=$tmux_session"
      fi
      tmp="$(mktemp)"
      jq --arg now "$(date -Is)" '.tmuxSession = null | .updatedAt = $now' "$task_file" > "$tmp"
      mv "$tmp" "$task_file"
      log "cleared tmux session for non-execution status: $task_id"
      log_event "tmux_cleared" "$task_id" "$status" "reason=non_execution_status"
    fi
    continue
  fi

  if [[ "$status" == "pending" || "$status" == "queued" ]]; then
    if "$START_TASK_SCRIPT" "$task_id" "$ROOT" >> "$LOG_FILE" 2>&1; then
      log "launch attempted: $task_id from_status=$status"
      log_event "launch_attempted" "$task_id" "$status" "source=reconcile"
    else
      log "launch attempt failed: $task_id from_status=$status"
      log_event "launch_attempt_failed" "$task_id" "$status" "source=reconcile"
    fi
    continue
  fi

  if [[ -n "$tmux_session" ]]; then
    if tmux has-session -t "$tmux_session" 2>/dev/null; then
      log "tmux session alive: $tmux_session"
      log_event "tmux_alive" "$task_id" "$status" "session=$tmux_session"
      if [[ "$status" == "pending" || "$status" == "retrying" ]]; then
        tmp="$(mktemp)"
        jq --arg now "$(date -Is)" '.status = "running" | .updatedAt = $now | .nextRetryAtEpoch = null' "$task_file" > "$tmp"
        mv "$tmp" "$task_file"
        log "normalized status to running: $task_id"
        log_event "status_changed" "$task_id" "running" "from=$status"
      fi
      continue
    fi
    log "tmux session missing: $tmux_session"
    log_event "tmux_missing" "$task_id" "$status" "session=$tmux_session"
  fi

  if [[ -f "$run_exit_file" ]]; then
    exit_code="$(jq -r '.exitCode // empty' "$run_exit_file" 2>/dev/null || true)"
    finished_at="$(jq -r '.finishedAt // empty' "$run_exit_file" 2>/dev/null || true)"
    if [[ -n "$exit_code" ]]; then
      if [[ "$exit_code" == "0" ]]; then
        tmp="$(mktemp)"
        jq \
          --arg now "$(date -Is)" \
          --arg finishedAt "$finished_at" \
          '.status = "ready_for_review"
          | .updatedAt = $now
          | .tmuxSession = null
          | .finishedAt = $finishedAt
          | .nextRetryAtEpoch = null' \
          "$task_file" > "$tmp"
        mv "$tmp" "$task_file"
        log "task process exited 0; marked ready_for_review: $task_id"
        log_event "status_changed" "$task_id" "ready_for_review" "reason=process_exit_0"
        continue
      fi
      failure_reason="agent_exit_code_$exit_code"
      log "task process exited non-zero: $task_id exit=$exit_code"
      log_event "process_exit_nonzero" "$task_id" "$status" "exitCode=$exit_code"
    fi
  fi

  if [[ "$status" == "retrying" ]]; then
    if "$START_TASK_SCRIPT" "$task_id" "$ROOT" >> "$LOG_FILE" 2>&1; then
      log "retry launch attempted: $task_id"
      log_event "retry_launch_attempted" "$task_id" "$status" "due=true"
    else
      log "retry launch failed: $task_id"
      log_event "retry_launch_failed" "$task_id" "$status" "start_task_failed"
    fi
    continue
  fi

  failure_reason="${failure_reason:-tmux_session_not_alive}"
  failure_class="$(classify_failure_class "$failure_reason" "$status" "$task_file")"
  retryable="$(policy_retryable "$failure_class")"
  effective_max_attempts="$(policy_max_attempts "$failure_class" "$max_attempts")"
  next_attempt=$((attempts + 1))

  if [[ "$retryable" != "true" ]]; then
    tmp="$(mktemp)"
    jq \
      --arg now "$(date -Is)" \
      --arg reason "$failure_reason" \
      --arg klass "$failure_class" \
      '.status = "failed"
      | .updatedAt = $now
      | .lastFailure.reason = $reason
      | .lastFailure.classification = $klass
      | .lastFailure.time = $now' \
      "$task_file" > "$tmp"
    mv "$tmp" "$FAILED_DIR/$task_id.json"
    rm -f "$task_file"
    log "marked failed (non-retryable class): $task_id class=$failure_class"
    log_event "task_failed" "$task_id" "failed" "reason=$failure_reason class=$failure_class retryable=false"
    continue
  fi

  if (( next_attempt <= effective_max_attempts )); then
    backoff_seconds="$(policy_backoff_seconds_for_attempt "$failure_class" "$next_attempt")"
    retry_after_epoch=$(( $(date +%s) + backoff_seconds ))
    tmp="$(mktemp)"
    jq \
      --arg reason "$failure_reason" \
      --arg klass "$failure_class" \
      --arg now "$(date -Is)" \
      --argjson next_retry "$retry_after_epoch" \
      --argjson attempt "$next_attempt" \
      '.attemptCount = $attempt
      | .status = "retrying"
      | .updatedAt = $now
      | .lastFailure.reason = $reason
      | .lastFailure.classification = $klass
      | .lastFailure.time = $now
      | .nextRetryAtEpoch = $next_retry
      | .tmuxSession = null' \
      "$task_file" > "$tmp"
    mv "$tmp" "$task_file"
    log "marked retrying: $task_id attempt=$next_attempt/$effective_max_attempts class=$failure_class backoff=${backoff_seconds}s"
    log_event "status_changed" "$task_id" "retrying" "attempt=$next_attempt class=$failure_class backoff=${backoff_seconds}s"

    if [[ -x "$ADJUST_PROMPT_SCRIPT" ]]; then
      if "$ADJUST_PROMPT_SCRIPT" "$task_file" "$failure_reason" "$next_attempt" "$failure_class" >> "$LOG_FILE" 2>&1; then
        log "prompt adjusted for retry: $task_id"
        log_event "prompt_adjusted" "$task_id" "retrying" "reason=$failure_reason class=$failure_class"
      else
        log "prompt adjust failed: $task_id"
        log_event "prompt_adjust_failed" "$task_id" "retrying" "reason=$failure_reason class=$failure_class"
      fi
    fi
  else
    tmp="$(mktemp)"
    jq \
      --arg now "$(date -Is)" \
      --arg reason "$failure_reason" \
      --arg klass "$failure_class" \
      '.status = "failed"
      | .updatedAt = $now
      | .lastFailure.reason = $reason
      | .lastFailure.classification = $klass' \
      "$task_file" > "$tmp"
    mv "$tmp" "$FAILED_DIR/$task_id.json"
    rm -f "$task_file"
    log "marked failed: $task_id class=$failure_class attempts_exhausted=$next_attempt/$effective_max_attempts"
    log_event "task_failed" "$task_id" "failed" "reason=$failure_reason class=$failure_class exhausted=true"
  fi
done

log "reconcile completed"
