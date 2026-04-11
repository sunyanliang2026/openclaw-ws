#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 [--review-ttl-hours <n>] [--fix] [runtime_root]"
}

REVIEW_TTL_HOURS=72
FIX=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --review-ttl-hours)
      REVIEW_TTL_HOURS="${2:-}"
      shift 2
      ;;
    --fix)
      FIX=1
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
ACTIVE_DIR="$ROOT/tasks/active"
ARCHIVE_SCRIPT="/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/archive-task.sh"

if [[ ! "$REVIEW_TTL_HOURS" =~ ^[0-9]+$ ]]; then
  echo "invalid --review-ttl-hours: $REVIEW_TTL_HOURS"
  exit 1
fi

require_bin() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing binary: $1"
    exit 1
  }
}

require_bin jq
require_bin date

mkdir -p "$ACTIVE_DIR"

ok=0
warn=0
fixed=0
fail=0

now_epoch="$(date +%s)"
shopt -s nullglob
for task_file in "$ACTIVE_DIR"/*.json; do
  task_id="$(basename "$task_file" .json)"
  status="$(jq -r '.status // "pending"' "$task_file")"
  updated_at="$(jq -r '.updatedAt // empty' "$task_file")"
  updated_epoch="$(date -d "$updated_at" +%s 2>/dev/null || true)"

  case "$status" in
    pending|queued|running|retrying|ready_for_review|needs_update|ci_running|ci_failed)
      ;;
    *)
      echo "WARN task=$task_id invalid_status=$status"
      warn=$((warn + 1))
      continue
      ;;
  esac

  if [[ "$status" == "ready_for_review" ]] && [[ -n "$updated_epoch" ]]; then
    age_hours=$(( (now_epoch - updated_epoch) / 3600 ))
    if (( age_hours >= REVIEW_TTL_HOURS )); then
      if (( FIX == 1 )); then
        if "$ARCHIVE_SCRIPT" --force --reason other --note "auto-archive stale ready_for_review (${age_hours}h)" "$task_id" "$ROOT" >/dev/null 2>&1; then
          echo "FIX  task=$task_id archived stale ready_for_review ageHours=$age_hours"
          fixed=$((fixed + 1))
        else
          echo "FAIL task=$task_id archive_failed ageHours=$age_hours"
          fail=$((fail + 1))
        fi
      else
        echo "WARN task=$task_id stale_ready_for_review ageHours=$age_hours"
        warn=$((warn + 1))
      fi
      continue
    fi
  fi

  ok=$((ok + 1))
done

echo "SUMMARY ok=$ok warn=$warn fixed=$fixed fail=$fail"
if (( fail > 0 )); then
  exit 2
fi

exit 0
