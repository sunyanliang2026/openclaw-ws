#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/home/ubuntu/.openclaw/workspace/openclaw-optimizer/runtime}"

require_bin() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing binary: $1"
    exit 1
  }
}

require_bin jq

summary() {
  local dir="$1"
  local label="$2"
  local count
  shopt -s nullglob
  local files=("$dir"/*.json)
  count=${#files[@]}
  echo "$label: $count"
  if (( count > 0 )); then
    jq -r '[.id, .status, (.branch // "-"), (.tmuxSession // "-")] | @tsv' "${files[@]}" \
      | awk 'BEGIN{print "  id\tstatus\tbranch\ttmux"} {print "  "$0}'
  fi
}

mkdir -p "$ROOT/tasks/active" "$ROOT/tasks/completed" "$ROOT/tasks/failed" "$ROOT/tasks/stopped" "$ROOT/tasks/archived"
summary "$ROOT/tasks/active" "active"
summary "$ROOT/tasks/completed" "completed"
summary "$ROOT/tasks/failed" "failed"
summary "$ROOT/tasks/stopped" "stopped"
summary "$ROOT/tasks/archived" "archived"
