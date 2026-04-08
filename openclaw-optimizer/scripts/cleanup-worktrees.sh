#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/home/ubuntu/.openclaw/workspace/openclaw-optimizer/runtime}"
WORKTREE_ROOT="${WORKTREE_ROOT:-/home/ubuntu/.openclaw/workspace/worktrees}"
LOG_DIR="$ROOT/logs"
LOG_FILE="$LOG_DIR/cleanup-$(date +%Y%m%d).log"
DRY_RUN="${DRY_RUN:-0}"

mkdir -p "$LOG_DIR"

log() {
  echo "[$(date -Is)] $*" | tee -a "$LOG_FILE"
}

require_bin() {
  command -v "$1" >/dev/null 2>&1 || {
    log "missing binary: $1"
    exit 1
  }
}

require_bin jq
require_bin git
require_bin tmux

if [[ ! -d "$WORKTREE_ROOT" ]]; then
  log "skip: worktree root does not exist: $WORKTREE_ROOT"
  exit 0
fi

declare -A keep_paths=()
for status_dir in "$ROOT/tasks/active" "$ROOT/tasks/completed" "$ROOT/tasks/failed" "$ROOT/tasks/stopped"; do
  [[ -d "$status_dir" ]] || continue
  shopt -s nullglob
  for f in "$status_dir"/*.json; do
    path="$(jq -r '.worktreePath // empty' "$f")"
    [[ -n "$path" ]] && keep_paths["$path"]=1
  done
done

shopt -s nullglob
for wt in "$WORKTREE_ROOT"/*; do
  [[ -d "$wt" ]] || continue
  if [[ -n "${keep_paths[$wt]:-}" ]]; then
    continue
  fi

  session="agent-$(basename "$wt")"
  if tmux has-session -t "$session" 2>/dev/null; then
    log "keep (tmux alive): $wt session=$session"
    continue
  fi

  repo_root="$(git -C "$wt" rev-parse --show-superproject-working-tree 2>/dev/null || true)"
  if [[ -z "$repo_root" ]]; then
    repo_root="$(git -C "$wt" rev-parse --show-toplevel 2>/dev/null || true)"
  fi

  if [[ -z "$repo_root" || ! -e "$repo_root/.git" ]]; then
    log "skip (not a recognized git worktree): $wt"
    continue
  fi

  if [[ "$DRY_RUN" == "1" ]]; then
    log "dry-run remove: $wt"
    continue
  fi

  if git -C "$repo_root" worktree remove "$wt" --force >/dev/null 2>&1; then
    log "removed orphan worktree: $wt"
  else
    log "failed remove orphan worktree: $wt"
  fi
done

log "cleanup completed"
