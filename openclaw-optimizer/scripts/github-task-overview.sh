#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/home/ubuntu/.openclaw/workspace/openclaw-optimizer/runtime}"
ACTIVE_DIR="$ROOT/tasks/active"

require_bin() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing binary: $1"
    exit 1
  }
}

require_bin jq
require_bin gh
require_bin git

mkdir -p "$ACTIVE_DIR"
shopt -s nullglob
files=("$ACTIVE_DIR"/*.json)

if (( ${#files[@]} == 0 )); then
  echo "no active tasks"
  exit 0
fi

echo "task_id	status	pr_url	pr_state	checks	mergeable	behind"
for f in "${files[@]}"; do
  task_id="$(basename "$f" .json)"
  status="$(jq -r '.status // ""' "$f")"
  pr_url="$(jq -r '.prUrl // empty' "$f")"
  repo_path="$(jq -r '.repoPath // empty' "$f")"
  branch="$(jq -r '.branch // empty' "$f")"

  if [[ -z "$pr_url" ]]; then
    echo -e "${task_id}\t${status}\t-\t-\t-\t-\t-"
    continue
  fi

  if [[ "$pr_url" =~ github\.com/([^/]+)/([^/]+)/pull/([0-9]+) ]]; then
    owner="${BASH_REMATCH[1]}"
    repo="${BASH_REMATCH[2]}"
    num="${BASH_REMATCH[3]}"
    api="repos/${owner}/${repo}/pulls/${num}"
    pr_state="$(gh api "$api" --jq '.state' 2>/dev/null || echo "UNKNOWN")"
    mergeable="$(gh api "$api" --jq '.mergeable' 2>/dev/null || echo "UNKNOWN")"
    checks="$(gh api "$api" --jq '.mergeable_state // "unknown"' 2>/dev/null || echo "unknown")"
  else
    pr_state="UNKNOWN"
    mergeable="UNKNOWN"
    checks="unknown"
  fi

  behind="-"
  if [[ -n "$repo_path" && -n "$branch" && -d "$repo_path/.git" ]]; then
    base="$(gh api "$api" --jq '.base.ref' 2>/dev/null || echo "")"
    if [[ -n "$base" ]]; then
      git -C "$repo_path" fetch origin "$base" "$branch" >/dev/null 2>&1 || true
      behind="$(git -C "$repo_path" rev-list --left-right --count "origin/$base...$branch" 2>/dev/null | awk '{print $1}' || echo "-")"
    fi
  fi

  echo -e "${task_id}\t${status}\t${pr_url}\t${pr_state}\t${checks}\t${mergeable}\t${behind}"
done
