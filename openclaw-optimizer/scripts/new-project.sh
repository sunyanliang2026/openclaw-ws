#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="/home/ubuntu/.openclaw/workspace/openclaw-optimizer"
PROJECT_DIR="$ROOT_DIR/projects"

usage() {
  cat <<USAGE
Usage:
  $0 --id <project_id> --name <name> --repo <repo_path> [--base main] [--worktree-root path] [--default-branch-prefix feat] [--default-type backend-feature] [--default-priority medium] [--default-agent codex] [--verification-command "pnpm test"] [--require-pr true|false] [--smoke-task-no-branch true|false]
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
default_branch_prefix="feat"
verification_command=""
require_pr="true"
smoke_task_no_branch="false"

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
    --default-branch-prefix)
      default_branch_prefix="${2:-$default_branch_prefix}"
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
    --verification-command)
      verification_command="${2:-$verification_command}"
      shift 2
      ;;
    --require-pr)
      require_pr="${2:-$require_pr}"
      shift 2
      ;;
    --smoke-task-no-branch)
      smoke_task_no_branch="${2:-$smoke_task_no_branch}"
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

normalize_bool() {
  local raw="$1"
  local lowered
  lowered="$(tr '[:upper:]' '[:lower:]' <<< "$raw")"
  case "$lowered" in
    true|1|yes) echo "true" ;;
    false|0|no) echo "false" ;;
    *) echo "" ;;
  esac
}

require_pr="$(normalize_bool "$require_pr")"
smoke_task_no_branch="$(normalize_bool "$smoke_task_no_branch")"
if [[ -z "$require_pr" || -z "$smoke_task_no_branch" ]]; then
  echo "invalid boolean for --require-pr or --smoke-task-no-branch"
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
  --arg bp "$default_branch_prefix" \
  --arg vc "$verification_command" \
  --argjson requirePr "$require_pr" \
  --argjson smokeNoBranch "$smoke_task_no_branch" \
  '{
    id:$id,
    name:$name,
    repoPath:$repo,
    baseBranch:$base,
    worktreeRoot:$wt,
    defaultBranchPrefix:$bp,
    defaultTaskType:$t,
    defaultPriority:$p,
    defaultAgent:$a,
    verificationCommand: (if $vc == "" then null else $vc end),
    requirePr:$requirePr,
    smokeTaskNoBranch:$smokeNoBranch,
    defaultPromptTemplate:"prompts/backend-feature-with-client-context.md",
    defaultSkills:["orchestrator","pr-quality-gate"],
    constraints:[],
    successCriteria:[]
  }' > "$project_file"

echo "created project manifest: $project_file"
