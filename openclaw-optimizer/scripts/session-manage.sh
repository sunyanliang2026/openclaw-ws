#!/usr/bin/env bash
set -euo pipefail

ROOT="${2:-/home/ubuntu/.openclaw/workspace/openclaw-optimizer/runtime}"
ACTIVE_DIR="$ROOT/tasks/active"
CMD="${1:-list}"

usage() {
  cat <<USAGE
Usage:
  $0 list [runtime_root]
  $0 attach <session_name>
  $0 kill-orphans [runtime_root]
USAGE
}

require_bin() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing binary: $1"
    exit 1
  }
}

require_bin tmux
require_bin jq

case "$CMD" in
  list)
    mkdir -p "$ACTIVE_DIR"
    echo "[active task sessions]"
    shopt -s nullglob
    for f in "$ACTIVE_DIR"/*.json; do
      task_id="$(basename "$f" .json)"
      session="$(jq -r '.tmuxSession // empty' "$f")"
      status="$(jq -r '.status // empty' "$f")"
      [[ -z "$session" ]] && continue
      if tmux has-session -t "$session" 2>/dev/null; then
        echo "OK   task=$task_id status=$status session=$session"
      else
        echo "WARN task=$task_id status=$status stale_session=$session"
      fi
    done
    echo "[all tmux sessions]"
    tmux list-sessions -F '#S' 2>/dev/null || echo "no tmux sessions"
    ;;
  attach)
    session="${2:-}"
    if [[ -z "$session" ]]; then
      usage
      exit 1
    fi
    exec tmux attach-session -t "$session"
    ;;
  kill-orphans)
    mkdir -p "$ACTIVE_DIR"
    ref_file="$(mktemp)"
    trap 'rm -f "$ref_file"' EXIT
    shopt -s nullglob
    for f in "$ACTIVE_DIR"/*.json; do
      s="$(jq -r '.tmuxSession // empty' "$f")"
      [[ -n "$s" ]] && printf '%s\n' "$s" >> "$ref_file"
    done
    if ! tmux ls >/dev/null 2>&1; then
      echo "no tmux server running"
      exit 0
    fi
    while IFS= read -r s; do
      [[ "$s" != agent-* ]] && continue
      if ! grep -Fxq "$s" "$ref_file"; then
        tmux kill-session -t "$s" >/dev/null 2>&1 || true
        echo "killed orphan session: $s"
      fi
    done < <(tmux list-sessions -F '#S')
    ;;
  *)
    usage
    exit 1
    ;;
esac
