#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 [--days <n>] [--dry-run] [runtime_root]"
}

RETENTION_DAYS=14
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --days)
      RETENTION_DAYS="${2:-}"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      break
      ;;
  esac
done

ROOT="${1:-/home/ubuntu/.openclaw/workspace/openclaw-optimizer/runtime}"
ARCHIVED_DIR="$ROOT/tasks/archived"
RUNS_DIR="$ROOT/task-runs"
LOCK_DIR="$ROOT/locks"
LOG_DIR="$ROOT/logs"
EVENT_DIR="$ROOT/events"
LOCK_FILE="$LOCK_DIR/cleanup-archives.lock"
LOG_FILE="$LOG_DIR/archive-cleanup-$(date +%Y%m%d).log"
EVENT_FILE="$EVENT_DIR/archive-cleanup-events-$(date +%Y%m%d).jsonl"

if [[ ! "$RETENTION_DAYS" =~ ^[0-9]+$ ]]; then
  echo "invalid --days: $RETENTION_DAYS"
  exit 1
fi

require_bin() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing binary: $1"
    exit 1
  }
}

require_bin jq
require_bin flock
require_bin date

mkdir -p "$ARCHIVED_DIR" "$RUNS_DIR" "$LOCK_DIR" "$LOG_DIR" "$EVENT_DIR"

log() {
  echo "[$(date -Is)] $*" | tee -a "$LOG_FILE"
}

log_event() {
  local event="$1"
  local task_id="$2"
  local detail="$3"
  jq -cn \
    --arg ts "$(date -Is)" \
    --arg event "$event" \
    --arg taskId "$task_id" \
    --arg detail "$detail" \
    '{ts:$ts,event:$event,taskId:$taskId,detail:$detail}' >> "$EVENT_FILE"
}

exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  log "another archive cleanup run is in progress; skipping"
  log_event "cleanup_skipped_locked" "" "lock=$LOCK_FILE"
  exit 0
fi

now_epoch="$(date +%s)"
removed=0
candidates=0

shopt -s nullglob
for task_file in "$ARCHIVED_DIR"/*.json; do
  task_id="$(basename "$task_file" .json)"

  ts="$(jq -r '.archivedAt // .updatedAt // empty' "$task_file" 2>/dev/null || true)"
  if [[ -n "$ts" ]]; then
    task_epoch="$(date -d "$ts" +%s 2>/dev/null || true)"
  else
    task_epoch=""
  fi

  if [[ -z "$task_epoch" ]]; then
    task_epoch="$(stat -c %Y "$task_file" 2>/dev/null || true)"
  fi

  if [[ -z "$task_epoch" ]]; then
    log "skip task=$task_id reason=no_timestamp"
    log_event "cleanup_skipped" "$task_id" "reason=no_timestamp"
    continue
  fi

  age_days=$(( (now_epoch - task_epoch) / 86400 ))
  if (( age_days < RETENTION_DAYS )); then
    continue
  fi

  candidates=$((candidates + 1))
  run_dir="$RUNS_DIR/$task_id"
  task_lock="$LOCK_DIR/start-task-$task_id.lock"

  if (( DRY_RUN == 1 )); then
    log "dry-run remove task=$task_id ageDays=$age_days file=$task_file runDir=$run_dir lock=$task_lock"
    log_event "cleanup_candidate" "$task_id" "ageDays=$age_days dryRun=true"
    continue
  fi

  rm -f "$task_file"
  rm -rf "$run_dir"
  rm -f "$task_lock"
  removed=$((removed + 1))

  log "removed archived task=$task_id ageDays=$age_days"
  log_event "cleanup_removed" "$task_id" "ageDays=$age_days"
done

log "archive cleanup done retentionDays=$RETENTION_DAYS candidates=$candidates removed=$removed dryRun=$DRY_RUN"
log_event "cleanup_finished" "" "retentionDays=$RETENTION_DAYS candidates=$candidates removed=$removed dryRun=$DRY_RUN"
