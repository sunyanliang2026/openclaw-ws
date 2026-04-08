#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="/home/ubuntu/.openclaw/workspace/openclaw-optimizer"
PROJECT_DIR="$ROOT_DIR/projects"

usage() {
  cat <<USAGE
Usage:
  $0 --id <project_id> --name <name> --repo <repo_path> [--base main] [--worktree-root path] [--default-type backend-feature] [--default-priority medium] [--default-agent codex]
USAGE
}

require_bin() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing binary: $1"
    exit 1
  }
}

require_bin jq

project_id=""
project_name=""
repo_path=""
base_branch="main"
worktree_root="/home/ubuntu/.openclaw/workspace/worktrees"
default_type="backend-feature"
default_priority="medium"
default_agent="codex"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --id)
      project_id="${2:-}"
      shift 2
      ;;
    --name)
      project_name="${2:-}"
      shift 2
      ;;
    --repo)
      repo_path="${2:-}"
      shift 2
      ;;
    --base)
      base_branch="${2:-main}"
      shift 2
      ;;
    --worktree-root)
      worktree_root="${2:-$worktree_root}"
      shift 2
      ;;
    --default-type)
      default_type="${2:-$default_type}"
      shift 2
      ;;
    --default-priority)
      default_priority="${2:-$default_priority}"
      shift 2
      ;;
    --default-agent)
      default_agent="${2:-$default_agent}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown arg: $1"
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$project_id" || -z "$project_name" || -z "$repo_path" ]]; then
  usage
  exit 1
fi

mkdir -p "$PROJECT_DIR"
project_file="$PROJECT_DIR/$project_id.json"
if [[ -f "$project_file" ]]; then
  echo "project already exists: $project_file"
  exit 1
fi

jq -cn \
  --arg id "$project_id" \
  --arg name "$project_name" \
  --arg repo "$repo_path" \
  --arg base "$base_branch" \
  --arg wt "$worktree_root" \
  --arg t "$default_type" \
  --arg p "$default_priority" \
  --arg a "$default_agent" \
  '{
    id:$id,
    name:$name,
    repoPath:$repo,
    baseBranch:$base,
    worktreeRoot:$wt,
    defaultTaskType:$t,
    defaultPriority:$p,
    defaultAgent:$a,
    defaultPromptTemplate:"prompts/backend-feature-with-client-context.md",
    defaultSkills:["orchestrator","pr-quality-gate"],
    constraints:[],
    successCriteria:[]
  }' > "$project_file"

echo "created project manifest: $project_file"
