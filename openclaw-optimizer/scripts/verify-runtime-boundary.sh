#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$ROOT_DIR/.." && pwd)"
GITIGNORE_FILE="$REPO_ROOT/.gitignore"

required_patterns=(
  "openclaw-optimizer/runtime/events/"
  "openclaw-optimizer/runtime/logs/"
  "openclaw-optimizer/runtime/locks/"
  "openclaw-optimizer/runtime/task-runs/"
  "openclaw-optimizer/runtime/tasks/active/"
  "openclaw-optimizer/runtime/tasks/completed/"
  "openclaw-optimizer/runtime/tasks/failed/"
  "openclaw-optimizer/runtime/tasks/stopped/"
  "openclaw-optimizer/runtime/tasks/archived/"
  "openclaw-optimizer/runtime/summaries/"
)

missing=0

if [[ ! -f "$GITIGNORE_FILE" ]]; then
  echo "FAIL missing .gitignore at $GITIGNORE_FILE"
  exit 2
fi

for p in "${required_patterns[@]}"; do
  if grep -Fqx "$p" "$GITIGNORE_FILE"; then
    echo "OK   ignore pattern present: $p"
  else
    echo "FAIL missing ignore pattern: $p"
    missing=$((missing + 1))
  fi
done

tracked_runtime="$(git -C "$REPO_ROOT" ls-files 'openclaw-optimizer/runtime/**' | grep -v '^openclaw-optimizer/runtime/state/' || true)"
if [[ -n "$tracked_runtime" ]]; then
  echo "FAIL tracked runtime files detected (non-state):"
  echo "$tracked_runtime"
  missing=$((missing + 1))
else
  echo "OK   no tracked runtime files outside runtime/state/"
fi

if (( missing > 0 )); then
  exit 2
fi

exit 0
