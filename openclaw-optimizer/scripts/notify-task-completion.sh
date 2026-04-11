#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 --task-file <path> [--dry-run] [runtime_root]"
}

TASK_FILE=""
DRY_RUN=0
if [[ "${NOTIFY_TASK_COMPLETION_DRY_RUN:-false}" == "true" ]]; then
  DRY_RUN=1
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-file)
      TASK_FILE="${2:-}"
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
INBOUND_CONFIG="/home/ubuntu/.openclaw/workspace/openclaw-optimizer/config/inbound-feishu.json"
STATE_DIR="$ROOT/state/task-notify"
LOG_DIR="$ROOT/logs"
LOG_FILE="$LOG_DIR/task-notify-$(date +%Y%m%d).log"

if [[ -z "$TASK_FILE" || ! -f "$TASK_FILE" ]]; then
  usage
  exit 1
fi

require_bin() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing binary: $1"
    exit 1
  }
}

require_bin jq
require_bin openclaw

mkdir -p "$STATE_DIR" "$LOG_DIR"

task_id="$(jq -r '.id // empty' "$TASK_FILE")"
status="$(jq -r '.status // empty' "$TASK_FILE")"
if [[ -z "$task_id" ]]; then
  echo "task id missing: $TASK_FILE"
  exit 1
fi
if [[ "$status" != "completed" ]]; then
  echo "skip notify: task not completed ($task_id status=$status)"
  exit 0
fi

flag_file="$STATE_DIR/$task_id.sent"
if [[ -f "$flag_file" ]]; then
  echo "skip notify: already sent ($task_id)"
  exit 0
fi

notify_enabled="$(jq -r '.notify.enabled // false' "$TASK_FILE")"
notify_channel="$(jq -r '.notify.channel // ""' "$TASK_FILE")"
notify_account="$(jq -r '.notify.account // ""' "$TASK_FILE")"
notify_target="$(jq -r '.notify.target // ""' "$TASK_FILE")"

if [[ "$notify_enabled" != "true" || -z "$notify_target" ]]; then
  if [[ -f "$INBOUND_CONFIG" ]]; then
    cfg_enabled="$(jq -r '.completionNotify.enabled // false' "$INBOUND_CONFIG" 2>/dev/null || echo "false")"
    cfg_target="$(jq -r '.completionNotify.target // ""' "$INBOUND_CONFIG" 2>/dev/null || true)"
    if [[ "$cfg_enabled" == "true" && -n "$cfg_target" ]]; then
      notify_enabled="true"
      notify_channel="$(jq -r '.completionNotify.channel // "feishu"' "$INBOUND_CONFIG" 2>/dev/null || echo "feishu")"
      notify_account="$(jq -r '.completionNotify.account // "main"' "$INBOUND_CONFIG" 2>/dev/null || echo "main")"
      notify_target="$cfg_target"
    fi
  fi
fi

if [[ "$notify_enabled" != "true" || -z "$notify_target" ]]; then
  echo "skip notify: disabled or missing target ($task_id)"
  exit 0
fi

if [[ -z "$notify_channel" ]]; then
  notify_channel="feishu"
fi

title="$(jq -r '.title // ""' "$TASK_FILE")"
project="$(jq -r '.projectId // ""' "$TASK_FILE")"
branch="$(jq -r '.branch // ""' "$TASK_FILE")"
completed_at="$(jq -r '.completedAt // .updatedAt // ""' "$TASK_FILE")"
summary_file="$ROOT/summaries/$task_id.json"
evidence_line="$(jq -r '.verification.evidence // ""' "$TASK_FILE" | awk 'NF{print; exit}')"
if [[ -z "$evidence_line" ]]; then
  evidence_line="(no evidence line)"
fi

msg="[openclaw task completed]
id: $task_id
title: $title
project: $project
branch: $branch
completedAt: $completed_at
summary: $summary_file
evidence: $evidence_line"

send_args=(openclaw message send --channel "$notify_channel" --target "$notify_target" --message "$msg" --json)
if [[ -n "$notify_account" ]]; then
  send_args+=(--account "$notify_account")
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  printf '%s\n' "DRYRUN channel=$notify_channel account=$notify_account target=$notify_target"
  printf '%s\n' "$msg"
  exit 0
fi

if send_out="$("${send_args[@]}" 2>&1)"; then
  now="$(date -Is)"
  touch "$flag_file"
  tmp="$(mktemp)"
  jq --arg now "$now" '.notify.sentAt = $now | .notify.lastError = null' "$TASK_FILE" > "$tmp" && mv "$tmp" "$TASK_FILE"
  echo "[$now] notify sent task=$task_id channel=$notify_channel target=$notify_target" >> "$LOG_FILE"
  exit 0
fi

now="$(date -Is)"
tmp="$(mktemp)"
jq --arg now "$now" --arg err "$send_out" '.notify.lastError = $err | .updatedAt = $now' "$TASK_FILE" > "$tmp" && mv "$tmp" "$TASK_FILE"
echo "[$now] notify failed task=$task_id channel=$notify_channel target=$notify_target err=$send_out" >> "$LOG_FILE"
exit 2
