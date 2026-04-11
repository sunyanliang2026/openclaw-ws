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
  jq -r -cn \
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
ARCHIVE_TASK_SCRIPT="/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/archive-task.sh"
NOTIFY_TASK_COMPLETION_SCRIPT="/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/notify-task-completion.sh"
SUMMARY_SCRIPT="/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/write-task-summary.sh"

trim_text() {
  awk '{gsub(/^[[:space:]]+|[[:space:]]+$/, ""); print}' <<< "$1"
}

is_smoke_auto_complete_candidate() {
  local task_file="$1"
  local title prompt policy_smoke
  title="$(jq -r '.title // empty' "$task_file")"
  prompt="$(jq -r '.launch.initialPrompt // .launch.basePrompt // empty' "$task_file")"
  policy_smoke="$(jq -r '.policy.smokeTaskNoBranch // false' "$task_file")"
  if [[ "$policy_smoke" == "true" ]]; then
    return 0
  fi
  local haystack
  haystack="$(tr '[:upper:]' '[:lower:]' <<< "$title"$'\n'"$prompt")"
  if [[ "$haystack" =~ smoke|e2e|healthcheck|connectivity|链路验证|验证任务|start[[:space:]]*true ]]; then
    return 0
  fi
  return 1
}

build_success_evidence() {
  local task_file="$1"
  local run_exit_file="$2"
  local run_log_file="$3"
  local started_at finished_at command log_hint
  started_at="$(trim_text "$(jq -r '.startedAt // empty' "$task_file")")"
  finished_at="$(trim_text "$(jq -r '.finishedAt // empty' "$task_file")")"
  if [[ -z "$finished_at" ]]; then
    finished_at="$(trim_text "$(jq -r '.finishedAt // empty' "$run_exit_file" 2>/dev/null || true)")"
  fi
  command="$(trim_text "$(jq -r '.command // empty' "$run_exit_file" 2>/dev/null || true)")"
  log_hint="$(awk 'NF{print; exit}' "$run_log_file" 2>/dev/null || true)"
  log_hint="$(trim_text "$log_hint")"
  if [[ -z "$log_hint" ]]; then
    log_hint="(run.log has no non-empty line)"
  fi
  jq -r -cn \
    --arg startedAt "$started_at" \
    --arg finishedAt "$finished_at" \
    --arg command "$command" \
    --arg runLog "$run_log_file" \
    --arg logHint "$log_hint" \
    '$startedAt as $s
    | $finishedAt as $f
    | $command as $c
    | $runLog as $l
    | $logHint as $h
    | ("execution evidence\n"
      + "- startedAt: " + (if ($s|length) > 0 then $s else "unknown" end) + "\n"
      + "- finishedAt: " + (if ($f|length) > 0 then $f else "unknown" end) + "\n"
      + "- command: " + (if ($c|length) > 0 then $c else "unknown" end) + "\n"
      + "- runLog: " + $l + "\n"
      + "- runLogFirstLine: " + $h)'
}

notify_task_file() {
  local file="$1"
  local event="${2:-status_changed}"
  if [[ -x "$NOTIFY_TASK_COMPLETION_SCRIPT" && -f "$file" ]]; then
    "$NOTIFY_TASK_COMPLETION_SCRIPT" --task-file "$file" --event "$event" "$ROOT" >> "$LOG_FILE" 2>&1 || true
  fi
}

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

policy_retry_guard_max_transitions() {
  if [[ -f "$FAILURE_POLICY_CONFIG" ]]; then
    jq -r '.retryGuard.maxRetryingTransitions // 3' "$FAILURE_POLICY_CONFIG"
  else
    echo "3"
  fi
}

policy_retry_guard_archive_on_trigger() {
  if [[ -f "$FAILURE_POLICY_CONFIG" ]]; then
    jq -r '.retryGuard.archiveOnTrigger // false' "$FAILURE_POLICY_CONFIG"
  else
    echo "false"
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
  retry_guard_max="$(policy_retry_guard_max_transitions)"
  retry_guard_archive="$(policy_retry_guard_archive_on_trigger)"
  run_exit_file="$ROOT/task-runs/$task_id/exit.json"
  run_log_file="$ROOT/task-runs/$task_id/run.log"

  log "checking task=$task_id status=$status attempts=$attempts/$max_attempts"
  log_event "task_checked" "$task_id" "$status" "attempts=$attempts/$max_attempts"

  if [[ "$status" == "retrying" ]] && [[ "$retry_guard_max" =~ ^[0-9]+$ ]] && (( retry_guard_max >= 0 )) && (( attempts >= retry_guard_max )); then
    tmp="$(mktemp)"
    jq \
      --arg now "$(date -Is)" \
      --arg reason "retry_exhausted_by_policy" \
      --arg klass "infra" \
      --argjson maxTransitions "$retry_guard_max" \
      '.status = "failed"
      | .updatedAt = $now
      | .lastFailure.reason = $reason
      | .lastFailure.classification = $klass
      | .lastFailure.time = $now
      | .failureDetail = ("retrying transitions reached policy limit: " + ($maxTransitions|tostring))
      | .nextRetryAtEpoch = null
      | .tmuxSession = null' \
      "$task_file" > "$tmp"
    mv "$tmp" "$FAILED_DIR/$task_id.json"
    rm -f "$task_file"
    notify_task_file "$FAILED_DIR/$task_id.json" "retry_guard_failed"
    log "retry guard triggered; marked failed: $task_id attempts=$attempts maxRetryingTransitions=$retry_guard_max"
    log_event "task_failed_retry_guard" "$task_id" "failed" "attempts=$attempts maxRetryingTransitions=$retry_guard_max"

    if [[ "$retry_guard_archive" == "true" && -x "$ARCHIVE_TASK_SCRIPT" ]]; then
      if "$ARCHIVE_TASK_SCRIPT" --force --reason infra-only --note "auto-archived by retry guard attempts=$attempts limit=$retry_guard_max" "$task_id" "$ROOT" >/dev/null 2>&1; then
        notify_task_file "$ROOT/tasks/archived/$task_id.json" "retry_guard_archived"
        log "retry guard auto-archived task: $task_id"
        log_event "task_archived_retry_guard" "$task_id" "archived" "attempts=$attempts maxRetryingTransitions=$retry_guard_max"
      else
        log "retry guard archive failed: $task_id"
        log_event "task_archive_retry_guard_failed" "$task_id" "failed" "attempts=$attempts maxRetryingTransitions=$retry_guard_max"
      fi
    fi
    continue
  fi

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
        notify_task_file "$FAILED_DIR/$task_id.json" "run_timeout"
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
        notify_task_file "$FAILED_DIR/$task_id.json" "queue_timeout"
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
    evidence_existing="$(jq -r '.verification.evidence // empty' "$task_file")"
    if [[ -z "$evidence_existing" && -f "$run_exit_file" ]]; then
      exit_code_existing="$(jq -r '.exitCode // empty' "$run_exit_file" 2>/dev/null || true)"
      evidence_text="$(build_success_evidence "$task_file" "$run_exit_file" "$run_log_file")"
      if [[ "$status" == "ready_for_review" && "$exit_code_existing" == "0" ]] && is_smoke_auto_complete_candidate "$task_file"; then
        tmp="$(mktemp)"
        jq \
          --arg now "$(date -Is)" \
          --arg evidence "$evidence_text" \
          '.status = "completed"
          | .updatedAt = $now
          | .completedAt = (.completedAt // $now)
          | .verification.evidence = $evidence' \
          "$task_file" > "$tmp"
        mv "$tmp" "$COMPLETED_DIR/$task_id.json"
        rm -f "$task_file"
        if [[ -x "$SUMMARY_SCRIPT" ]]; then
          "$SUMMARY_SCRIPT" --task-file "$COMPLETED_DIR/$task_id.json" --stage updated "$ROOT" >/dev/null 2>&1 || true
        fi
        log "auto-completed legacy ready_for_review smoke/e2e task: $task_id"
        log_event "task_completed" "$task_id" "completed" "reason=legacy_ready_for_review_smoke_autoclose"
        notify_task_file "$COMPLETED_DIR/$task_id.json" "legacy_ready_for_review_smoke_autoclose"
        continue
      fi
      tmp="$(mktemp)"
      jq --arg now "$(date -Is)" --arg evidence "$evidence_text" '.verification.evidence = $evidence | .updatedAt = $now' "$task_file" > "$tmp"
      mv "$tmp" "$task_file"
      notify_task_file "$task_file" "evidence_backfilled"
      log "backfilled verification evidence for task: $task_id"
      log_event "evidence_backfilled" "$task_id" "$status" "source=run_exit_file"
    fi
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
        notify_task_file "$task_file" "normalized_running"
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
        evidence_text="$(build_success_evidence "$task_file" "$run_exit_file" "$run_log_file")"
        auto_complete="false"
        if is_smoke_auto_complete_candidate "$task_file"; then
          auto_complete="true"
        fi
        tmp="$(mktemp)"
        if [[ "$auto_complete" == "true" ]]; then
          jq \
            --arg now "$(date -Is)" \
            --arg finishedAt "$finished_at" \
            --arg evidence "$evidence_text" \
            '.status = "completed"
            | .updatedAt = $now
            | .tmuxSession = null
            | .finishedAt = $finishedAt
            | .completedAt = $now
            | .nextRetryAtEpoch = null
            | .verification.evidence = (if (.verification.evidence // "" | length) > 0 then .verification.evidence else $evidence end)' \
            "$task_file" > "$tmp"
          mv "$tmp" "$COMPLETED_DIR/$task_id.json"
          rm -f "$task_file"
          if [[ -x "$SUMMARY_SCRIPT" ]]; then
            "$SUMMARY_SCRIPT" --task-file "$COMPLETED_DIR/$task_id.json" --stage updated "$ROOT" >/dev/null 2>&1 || true
          fi
          log "task process exited 0; auto-completed smoke/e2e task: $task_id"
          log_event "task_completed" "$task_id" "completed" "reason=process_exit_0_smoke_autoclose"
          notify_task_file "$COMPLETED_DIR/$task_id.json" "process_exit_0_smoke_autoclose"
        else
          jq \
            --arg now "$(date -Is)" \
            --arg finishedAt "$finished_at" \
            --arg evidence "$evidence_text" \
            '.status = "ready_for_review"
            | .updatedAt = $now
            | .tmuxSession = null
            | .finishedAt = $finishedAt
            | .nextRetryAtEpoch = null
            | .verification.evidence = (if (.verification.evidence // "" | length) > 0 then .verification.evidence else $evidence end)' \
            "$task_file" > "$tmp"
          mv "$tmp" "$task_file"
          notify_task_file "$task_file" "process_exit_0_ready_for_review"
          log "task process exited 0; marked ready_for_review with evidence: $task_id"
          log_event "status_changed" "$task_id" "ready_for_review" "reason=process_exit_0_evidence_backfilled"
        fi
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
    notify_task_file "$FAILED_DIR/$task_id.json" "non_retryable_failed"
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
    notify_task_file "$task_file" "retrying"
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
    notify_task_file "$FAILED_DIR/$task_id.json" "attempts_exhausted_failed"
    log "marked failed: $task_id class=$failure_class attempts_exhausted=$next_attempt/$effective_max_attempts"
    log_event "task_failed" "$task_id" "failed" "reason=$failure_reason class=$failure_class exhausted=true"
  fi
done

log "reconcile completed"
