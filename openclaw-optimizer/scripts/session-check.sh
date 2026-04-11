#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 [--fix] [runtime_root]"
}

FIX=0
while [[ $# -gt 0 ]]; do
  case "$1" in
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

require_bin() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing binary: $1"
    exit 1
  }
}

require_bin jq
require_bin tmux

ok_count=0
warn_count=0
fail_count=0
fixed_count=0

ok() {
  ok_count=$((ok_count + 1))
  printf 'OK   %s\n' "$1"
}

warn() {
  warn_count=$((warn_count + 1))
  printf 'WARN %s\n' "$1"
}

fail() {
  fail_count=$((fail_count + 1))
  printf 'FAIL %s\n' "$1"
}

fix_note() {
  fixed_count=$((fixed_count + 1))
  printf 'FIX  %s\n' "$1"
}

mkdir -p "$ACTIVE_DIR"

ref_file="$(mktemp)"
trap 'rm -f "$ref_file"' EXIT

shopt -s nullglob
active_files=("$ACTIVE_DIR"/*.json)

for task_file in "${active_files[@]}"; do
  task_id="$(basename "$task_file" .json)"
  status="$(jq -r '.status // "pending"' "$task_file")"
  session="$(jq -r '.tmuxSession // empty' "$task_file")"

  if [[ -z "$session" ]]; then
    continue
  fi

  printf '%s\n' "$session" >> "$ref_file"

  if tmux has-session -t "$session" 2>/dev/null; then
    ok "task=$task_id status=$status session_alive=$session"
    continue
  fi

  if [[ "$status" == "running" || "$status" == "retrying" ]]; then
    if [[ "$FIX" -eq 1 ]]; then
      tmp="$(mktemp)"
      jq --arg now "$(date -Is)" '.tmuxSession = null | .updatedAt = $now' "$task_file" > "$tmp"
      mv "$tmp" "$task_file"
      fix_note "task=$task_id cleared_stale_session=$session"
    else
      fail "task=$task_id status=$status stale_session=$session"
    fi
  else
    if [[ "$FIX" -eq 1 ]]; then
      tmp="$(mktemp)"
      jq --arg now "$(date -Is)" '.tmuxSession = null | .updatedAt = $now' "$task_file" > "$tmp"
      mv "$tmp" "$task_file"
      fix_note "task=$task_id status=$status cleared_stale_session=$session"
    else
      warn "task=$task_id status=$status stale_session=$session"
    fi
  fi
done

if tmux ls >/dev/null 2>&1; then
  while IFS= read -r session; do
    [[ -z "$session" ]] && continue
    [[ "$session" != agent-* ]] && continue
    if ! grep -Fxq "$session" "$ref_file"; then
      if [[ "$FIX" -eq 1 ]]; then
        if tmux kill-session -t "$session" >/dev/null 2>&1; then
          fix_note "killed_orphan_session=$session"
        else
          warn "failed_to_kill_orphan_session=$session"
        fi
      else
        warn "orphan_session=$session"
      fi
    fi
  done < <(tmux list-sessions -F '#S' 2>/dev/null || true)
else
  ok "no_tmux_server"
fi

echo "SUMMARY ok=$ok_count warn=$warn_count fail=$fail_count fixed=$fixed_count active=${#active_files[@]}"

if (( fail_count > 0 )); then
  exit 2
fi

exit 0
