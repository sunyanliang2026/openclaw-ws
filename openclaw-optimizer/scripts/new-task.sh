#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="/home/ubuntu/.openclaw/workspace/openclaw-optimizer"
RUNTIME_ROOT="$ROOT_DIR/runtime"
PROJECT_DIR="$ROOT_DIR/projects"
ROUTING_CONFIG="$ROOT_DIR/config/agent-selection.json"
TASK_DIR="$RUNTIME_ROOT/tasks/active"

usage() {
  cat <<USAGE
Usage:
  $0 --project <project_id> --task-id <task_id> --title <text> [--type backend-feature] [--priority high|medium|low] [--branch feat/xxx] [--agent codex] [--prompt "..."] [--requirement file.md] [--notify-channel feishu] [--notify-account main] [--notify-target chat:oc_xxx]
USAGE
}

require_bin() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing binary: $1"
    exit 1
  }
}

slugify() {
  tr '[:upper:]' '[:lower:]' <<< "$1" \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-+/-/g'
}

require_bin jq

project_id=""
task_id=""
title=""
task_type=""
priority=""
branch=""
agent=""
prompt_text=""
requirement_file=""
notify_channel=""
notify_account=""
notify_target=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)
      project_id="${2:-}"
      shift 2
      ;;
    --task-id)
      task_id="${2:-}"
      shift 2
      ;;
    --title)
      title="${2:-}"
      shift 2
      ;;
    --type)
      task_type="${2:-}"
      shift 2
      ;;
    --priority)
      priority="${2:-}"
      shift 2
      ;;
    --branch)
      branch="${2:-}"
      shift 2
      ;;
    --agent)
      agent="${2:-}"
      shift 2
      ;;
    --prompt)
      prompt_text="${2:-}"
      shift 2
      ;;
    --requirement)
      requirement_file="${2:-}"
      shift 2
      ;;
    --notify-channel)
      notify_channel="${2:-}"
      shift 2
      ;;
    --notify-account)
      notify_account="${2:-}"
      shift 2
      ;;
    --notify-target)
      notify_target="${2:-}"
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

if [[ -z "$project_id" || -z "$task_id" || -z "$title" ]]; then
  usage
  exit 1
fi

project_file="$PROJECT_DIR/$project_id.json"
if [[ ! -f "$project_file" ]]; then
  echo "project not found: $project_file"
  exit 1
fi

mkdir -p "$TASK_DIR"
task_file="$TASK_DIR/$task_id.json"
if [[ -f "$task_file" ]]; then
  echo "task already exists: $task_file"
  exit 1
fi

repo_path="$(jq -r '.repoPath // empty' "$project_file")"
worktree_root="$(jq -r '.worktreeRoot // "/home/ubuntu/.openclaw/workspace/worktrees"' "$project_file")"
base_branch="$(jq -r '.baseBranch // "main"' "$project_file")"
default_branch_prefix="$(jq -r '.defaultBranchPrefix // "feat"' "$project_file")"
verification_command="$(jq -r '.verificationCommand // empty' "$project_file")"
require_pr="$(jq -r '.requirePr // true' "$project_file")"
smoke_task_no_branch="$(jq -r '.smokeTaskNoBranch // false' "$project_file")"

if [[ -z "$task_type" ]]; then
  task_type="$(jq -r '.defaultTaskType // "backend-feature"' "$project_file")"
fi
if [[ -z "$priority" ]]; then
  priority="$(jq -r '.defaultPriority // "medium"' "$project_file")"
fi
if [[ -z "$branch" ]]; then
  if [[ "$smoke_task_no_branch" == "true" && "$task_type" == "docs-changelog" ]]; then
    branch="$base_branch"
  else
    branch="${default_branch_prefix}/$(slugify "$task_id")"
  fi
fi

if [[ -z "$agent" && -f "$ROUTING_CONFIG" ]]; then
  agent="$(jq -r --arg t "$task_type" '.routing[$t].primary // empty' "$ROUTING_CONFIG")"
fi
if [[ -z "$agent" ]]; then
  agent="$(jq -r '.defaultAgent // "codex"' "$project_file")"
fi

if [[ -z "$prompt_text" ]]; then
  prompt_text="Task: $title\nProject: $project_id\nBranch: $branch\nPlease implement with tests and provide PR validation notes."
fi
if [[ -n "$requirement_file" && -f "$requirement_file" ]]; then
  req_body="$(cat "$requirement_file")"
  prompt_text="$prompt_text\n\nRequirement Brief:\n$req_body"
fi

worktree_path="$worktree_root/$task_id"
now_iso="$(date -Is)"
if [[ -z "$notify_channel" ]]; then
  notify_channel="feishu"
fi
if [[ -z "$notify_account" ]]; then
  notify_account="main"
fi
notify_enabled="false"
if [[ -n "$notify_target" ]]; then
  notify_enabled="true"
fi

jq -cn \
  --arg id "$task_id" \
  --arg project "$project_id" \
  --arg t "$task_type" \
  --arg p "$priority" \
  --arg repo "$repo_path" \
  --arg branch "$branch" \
  --arg wt "$worktree_path" \
  --arg agent "$agent" \
  --arg now "$now_iso" \
  --arg prompt "$prompt_text" \
  --arg title "$title" \
  --arg notifyChannel "$notify_channel" \
  --arg notifyAccount "$notify_account" \
  --arg notifyTarget "$notify_target" \
  --argjson notifyEnabled "$notify_enabled" \
  --arg verifyCmd "$verification_command" \
  --argjson requirePr "$require_pr" \
  --argjson smokeNoBranch "$smoke_task_no_branch" \
  --argjson constraints "$(jq -c '.constraints // []' "$project_file")" \
  --argjson success "$(jq -c '.successCriteria // []' "$project_file")" \
  --argjson skills "$(jq -c '.defaultSkills // []' "$project_file")" \
  '{
    id:$id,
    projectId:$project,
    title:$title,
    type:$t,
    priority:$p,
    repoPath:$repo,
    branch:$branch,
    worktreePath:$wt,
    agent:$agent,
    skills:$skills,
    status:"pending",
    queueReason:null,
    queuedAt:null,
    maxRunMinutes:180,
    maxQueueMinutes:240,
    attemptCount:0,
    maxAttempts:3,
    createdAt:$now,
    updatedAt:$now,
    tmuxSession:null,
    nextRetryAtEpoch:null,
    prUrl:null,
    launch:{
      command:null,
      initialPrompt:$prompt,
      basePrompt:$prompt
    },
    verification:{
      testCommand:$verifyCmd,
      testsPassed:false,
      evidence:""
    },
    notify:{
      enabled:$notifyEnabled,
      channel:$notifyChannel,
      account:$notifyAccount,
      target:(if ($notifyTarget|length) > 0 then $notifyTarget else null end),
      sentAt:null,
      lastError:null
    },
    policy:{
      requirePr:$requirePr,
      smokeTaskNoBranch:$smokeNoBranch
    },
    context:{
      project:$project,
      constraints:$constraints,
      successCriteria:$success
    },
    lastFailure:{
      time:null,
      reason:null,
      classification:null,
      promptAdjustment:null
    }
  }' > "$task_file"

echo "created task: $task_file"
echo "agent=$agent type=$task_type priority=$priority"
