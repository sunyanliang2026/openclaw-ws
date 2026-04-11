#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 [--force] [--reason merged|abandoned|duplicate|smoke-only|infra-only|other] [--note <text>] <task_id> [runtime_root]"
}

FORCE=0
ARCHIVE_REASON="other"
ARCHIVE_NOTE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)
      FORCE=1
      shift
      ;;
    --reason)
      ARCHIVE_REASON="${2:-}"
      shift 2
      ;;
    --note)
      ARCHIVE_NOTE="${2:-}"
      shift 2
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

TASK_ID="${1:-}"
ROOT="${2:-/home/ubuntu/.openclaw/workspace/openclaw-optimizer/runtime}"
SUMMARY_SCRIPT="/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/write-task-summary.sh"
NOTIFY_TASK_COMPLETION_SCRIPT="/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/notify-task-completion.sh"

if [[ -z "$TASK_ID" ]]; then
  usage
  exit 1
fi

case "$ARCHIVE_REASON" in
  merged|abandoned|duplicate|smoke-only|infra-only|other)
    ;;
  *)
    echo "invalid --reason: $ARCHIVE_REASON"
    exit 1
    ;;
esac

require_bin() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing binary: $1"
    exit 1
  }
}

require_bin jq
require_bin tmux

source_dir=""
source_file=""
for status_dir in active completed failed stopped; do
  candidate="$ROOT/tasks/$status_dir/$TASK_ID.json"
  if [[ -f "$candidate" ]]; then
    source_dir="$status_dir"
    source_file="$candidate"
    break
  fi
done

if [[ -z "$source_file" ]]; then
  archived_candidate="$ROOT/tasks/archived/$TASK_ID.json"
  if [[ -f "$archived_candidate" ]]; then
    echo "task already archived: $archived_candidate"
    exit 0
  fi
  echo "task not found in active/completed/failed/stopped: $TASK_ID"
  exit 1
fi

tmux_session="$(jq -r '.tmuxSession // empty' "$source_file")"
if [[ "$source_dir" == "active" && "$FORCE" -ne 1 ]]; then
  if [[ -n "$tmux_session" ]] && tmux has-session -t "$tmux_session" 2>/dev/null; then
    echo "refusing to archive active task with live tmux session: $TASK_ID"
    echo "rerun with --force if you really want to archive it"
    exit 1
  fi
  echo "refusing to archive task still in active queue: $TASK_ID"
  echo "move it to completed/failed/stopped first, or rerun with --force"
  exit 1
fi

archived_dir="$ROOT/tasks/archived"
mkdir -p "$archived_dir"

tmp="$(mktemp)"
jq \
  --arg now "$(date -Is)" \
  --arg archivedFrom "$source_dir" \
  --arg reason "$ARCHIVE_REASON" \
  --arg note "$ARCHIVE_NOTE" \
  '.status = "archived"
  | .updatedAt = $now
  | .archivedAt = $now
  | .archivedFrom = $archivedFrom
  | .archive = {
      reason: $reason,
      note: (if $note == "" then null else $note end)
    }' \
  "$source_file" > "$tmp"

mv "$tmp" "$archived_dir/$TASK_ID.json"
rm -f "$source_file"

if [[ -x "$SUMMARY_SCRIPT" ]]; then
  "$SUMMARY_SCRIPT" --task-file "$archived_dir/$TASK_ID.json" --stage archived "$ROOT" >/dev/null 2>&1 || true
fi
if [[ -x "$NOTIFY_TASK_COMPLETION_SCRIPT" ]]; then
  "$NOTIFY_TASK_COMPLETION_SCRIPT" --task-file "$archived_dir/$TASK_ID.json" --event "task_archived_$ARCHIVE_REASON" "$ROOT" >/dev/null 2>&1 || true
fi

echo "archived task=$TASK_ID from=$source_dir reason=$ARCHIVE_REASON"
