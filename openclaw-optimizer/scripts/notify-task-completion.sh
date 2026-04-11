#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 --task-file <path> [--event <text>] [--dry-run] [runtime_root]"
}

TASK_FILE=""
EVENT_HINT=""
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
    --event)
      EVENT_HINT="${2:-}"
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
if [[ -z "$task_id" || -z "$status" ]]; then
  echo "skip notify: missing id/status"
  exit 0
fi

case "$status" in
  running|queued|retrying|ready_for_review|needs_update|ci_running|ci_failed|completed|failed|stopped|archived)
    ;;
  *)
    echo "skip notify: status not in notify scope ($task_id status=$status)"
    exit 0
    ;;
esac

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
  echo "skip notify: disabled or missing target ($task_id status=$status)"
  exit 0
fi

if [[ -z "$notify_channel" ]]; then
  notify_channel="feishu"
fi

fingerprint_raw="$(jq -c '{status,attemptCount,lastFailure,prUrl,archive,qualityGate,notify}' "$TASK_FILE")"
if command -v sha256sum >/dev/null 2>&1; then
  fingerprint="$(printf '%s' "$fingerprint_raw" | sha256sum | awk '{print $1}')"
else
  fingerprint="$(printf '%s' "$fingerprint_raw" | shasum -a 256 | awk '{print $1}')"
fi

state_file="$STATE_DIR/$task_id.json"
last_fp=""
if [[ -f "$state_file" ]]; then
  last_fp="$(jq -r --arg s "$status" '.sent[$s].fingerprint // empty' "$state_file" 2>/dev/null || true)"
fi
if [[ -n "$last_fp" && "$last_fp" == "$fingerprint" ]]; then
  echo "skip notify: duplicate fingerprint ($task_id status=$status)"
  exit 0
fi

title="$(jq -r '.title // ""' "$TASK_FILE")"
project="$(jq -r '.projectId // ""' "$TASK_FILE")"
branch="$(jq -r '.branch // ""' "$TASK_FILE")"
attempt_count="$(jq -r '.attemptCount // 0' "$TASK_FILE")"
pr_url="$(jq -r '.prUrl // ""' "$TASK_FILE")"
updated_at="$(jq -r '.updatedAt // ""' "$TASK_FILE")"
reason="$(jq -r '.lastFailure.reason // ""' "$TASK_FILE")"
klass="$(jq -r '.lastFailure.classification // ""' "$TASK_FILE")"
summary_file="$ROOT/summaries/$task_id.json"
evidence_line="$(jq -r '.verification.evidence // ""' "$TASK_FILE" | awk 'NF{print; exit}')"
if [[ -z "$evidence_line" ]]; then
  evidence_line="(no evidence line)"
fi

msg="[openclaw task status]
id: $task_id
title: $title
project: $project
status: $status
attempt: $attempt_count
branch: $branch
updatedAt: $updated_at"

if [[ -n "$EVENT_HINT" ]]; then
  msg="$msg
event: $EVENT_HINT"
fi
if [[ -n "$reason" ]]; then
  msg="$msg
failure: $reason ($klass)"
fi
if [[ -n "$pr_url" ]]; then
  msg="$msg
pr: $pr_url"
fi
if [[ "$status" == "completed" || "$status" == "ready_for_review" || "$status" == "needs_update" ]]; then
  msg="$msg
evidence: $evidence_line"
fi
msg="$msg
summary: $summary_file"

send_args=(openclaw message send --channel "$notify_channel" --target "$notify_target" --message "$msg" --json)
if [[ -n "$notify_account" ]]; then
  send_args+=(--account "$notify_account")
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  printf '%s\n' "DRYRUN channel=$notify_channel account=$notify_account target=$notify_target status=$status"
  printf '%s\n' "$msg"
  exit 0
fi

if send_out="$("${send_args[@]}" 2>&1)"; then
  now="$(date -Is)"
  tmp_task="$(mktemp)"
  jq --arg now "$now" --arg st "$status" '.notify.sentAt = $now | .notify.lastStatus = $st | .notify.lastError = null' "$TASK_FILE" > "$tmp_task" && mv "$tmp_task" "$TASK_FILE"

  tmp_state="$(mktemp)"
  if [[ -f "$state_file" ]]; then
    jq --arg s "$status" --arg fp "$fingerprint" --arg now "$now" '.sent = (.sent // {}) | .sent[$s] = {fingerprint:$fp, sentAt:$now}' "$state_file" > "$tmp_state"
  else
    jq -cn --arg s "$status" --arg fp "$fingerprint" --arg now "$now" '{sent:{($s):{fingerprint:$fp,sentAt:$now}}}' > "$tmp_state"
  fi
  mv "$tmp_state" "$state_file"

  echo "[$now] notify sent task=$task_id status=$status channel=$notify_channel target=$notify_target" >> "$LOG_FILE"
  exit 0
fi

now="$(date -Is)"
tmp="$(mktemp)"
jq --arg now "$now" --arg err "$send_out" '.notify.lastError = $err | .updatedAt = $now' "$TASK_FILE" > "$tmp" && mv "$tmp" "$TASK_FILE"
echo "[$now] notify failed task=$task_id status=$status channel=$notify_channel target=$notify_target err=$send_out" >> "$LOG_FILE"
exit 2
