#!/usr/bin/env bash
set -euo pipefail

TASK_ID="${1:-}"
ROOT="${2:-/home/ubuntu/.openclaw/workspace/openclaw-optimizer/runtime}"

if [[ -z "$TASK_ID" ]]; then
  echo "Usage: $0 <task_id> [runtime_root]"
  exit 1
fi

BASE="/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts"
"$BASE/start-task.sh" "$TASK_ID" "$ROOT"
"$BASE/reconcile-tasks.sh" "$ROOT"
"$BASE/pr-check.sh" "$ROOT"
"$BASE/task-status.sh" "$ROOT"
