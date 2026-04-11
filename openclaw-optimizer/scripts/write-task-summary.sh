#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 --task-file <path> [--stage <stopped|archived|updated>] [runtime_root]"
}

TASK_FILE=""
STAGE="updated"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-file)
      TASK_FILE="${2:-}"
      shift 2
      ;;
    --stage)
      STAGE="${2:-}"
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

ROOT="${1:-/home/ubuntu/.openclaw/workspace/openclaw-optimizer/runtime}"

if [[ -z "$TASK_FILE" ]]; then
  usage
  exit 1
fi

if [[ ! -f "$TASK_FILE" ]]; then
  echo "task file not found: $TASK_FILE"
  exit 1
fi

require_bin() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing binary: $1"
    exit 1
  }
}

require_bin jq

summary_dir="$ROOT/summaries"
mkdir -p "$summary_dir"

task_id="$(jq -r '.id // empty' "$TASK_FILE")"
if [[ -z "$task_id" ]]; then
  echo "task id missing in: $TASK_FILE"
  exit 1
fi

tmp="$(mktemp)"
jq \
  --arg generatedAt "$(date -Is)" \
  --arg stage "$STAGE" \
  --arg taskFile "$TASK_FILE" \
  '{
    id: .id,
    projectId: (.projectId // null),
    title: (.title // null),
    type: (.type // null),
    priority: (.priority // null),
    status: (.status // null),
    branch: (.branch // null),
    repoPath: (.repoPath // null),
    worktreePath: (.worktreePath // null),
    tmuxSession: (.tmuxSession // null),
    prUrl: (.prUrl // null),
    verification: (.verification // null),
    lastFailure: (.lastFailure // null),
    archive: (.archive // null),
    archivedAt: (.archivedAt // null),
    archivedFrom: (.archivedFrom // null),
    createdAt: (.createdAt // null),
    startedAt: (.startedAt // null),
    finishedAt: (.finishedAt // null),
    updatedAt: (.updatedAt // null),
    summaryMeta: {
      generatedAt: $generatedAt,
      stage: $stage,
      taskFile: $taskFile
    }
  }' \
  "$TASK_FILE" > "$tmp"

mv "$tmp" "$summary_dir/$task_id.json"
echo "wrote summary: $summary_dir/$task_id.json"
