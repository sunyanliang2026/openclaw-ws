#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 [--keep-worktree] [--result completed|failed|stopped] <task_id> [runtime_root]"
}

KEEP_WORKTREE=0
RESULT="stopped"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --keep-worktree)
      KEEP_WORKTREE=1
      shift
      ;;
    --result)
      RESULT="${2:-}"
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

if [[ -z "$TASK_ID" ]]; then
  usage
  exit 1
fi

if [[ "$RESULT" != "completed" && "$RESULT" != "failed" && "$RESULT" != "stopped" ]]; then
  echo "invalid --result: $RESULT"
  exit 1
fi

ACTIVE_FILE="$ROOT/tasks/active/$TASK_ID.json"
if [[ ! -f "$ACTIVE_FILE" ]]; then
  echo "active task not found: $ACTIVE_FILE"
  exit 1
fi

require_bin() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing binary: $1"
    exit 1
  }
}

require_bin jq
require_bin tmux
require_bin git

repo_path="$(jq -r '.repoPath // empty' "$ACTIVE_FILE")"
worktree_path="$(jq -r '.worktreePath // empty' "$ACTIVE_FILE")"
session="$(jq -r '.tmuxSession // empty' "$ACTIVE_FILE")"

if [[ -n "$session" ]] && tmux has-session -t "$session" 2>/dev/null; then
  tmux kill-session -t "$session" || true
fi

if [[ "$KEEP_WORKTREE" -eq 0 && -n "$worktree_path" && -n "$repo_path" && -e "$repo_path/.git" ]]; then
  git -C "$repo_path" worktree remove "$worktree_path" --force >/dev/null 2>&1 || true
fi

dst_dir="$ROOT/tasks/$RESULT"
mkdir -p "$dst_dir"

tmp="$(mktemp)"
jq --arg result "$RESULT" --arg now "$(date -Is)" '.status = $result | .updatedAt = $now' "$ACTIVE_FILE" > "$tmp"
mv "$tmp" "$dst_dir/$TASK_ID.json"
rm -f "$ACTIVE_FILE"

echo "stopped task=$TASK_ID result=$RESULT"
