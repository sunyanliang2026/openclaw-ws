#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="/home/ubuntu/.openclaw/workspace/openclaw-optimizer"
RUNTIME_ROOT="$ROOT_DIR/runtime"
INBOUND_CONFIG="$ROOT_DIR/config/inbound-feishu.json"
NEW_TASK_SCRIPT="$ROOT_DIR/scripts/new-task.sh"
START_TASK_SCRIPT="$ROOT_DIR/scripts/start-task.sh"
EVENT_DIR="$RUNTIME_ROOT/events"
EVENT_FILE="$EVENT_DIR/feishu-command-events-$(date +%Y%m%d).jsonl"
LOCK_DIR="$RUNTIME_ROOT/locks"
DISPATCH_LOCK_FILE="$LOCK_DIR/feishu-command-dispatch.lock"
CMD_EXAMPLE="/newtask | title: ... | project: internal-openclaw | type: backend-feature | priority: medium | start: true | prompt: ..."
PROJECT_DIR="$ROOT_DIR/projects"
TASK_ROOT="$RUNTIME_ROOT/tasks"
ALLOWED_TYPES=("backend-feature" "frontend-feature" "bug-fix" "docs-changelog")
ALLOWED_PRIORITIES=("high" "medium" "low")

usage() {
  cat <<USAGE
Usage:
  $0 --text "<message>" [--start true|false]
  $0 --file <path/to/message.txt> [--start true|false]

Command format:
  /newtask
  title: Build marketing site
  project: internal-openclaw
  type: frontend-feature
  priority: high
  id: optional-task-id
  start: true
  prompt: Implement a responsive marketing site...
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

trim_text() {
  awk '{gsub(/^[[:space:]]+|[[:space:]]+$/, ""); print}' <<< "$1"
}

log_event() {
  local event="$1"
  local detail="$2"
  mkdir -p "$EVENT_DIR"
  jq -cn \
    --arg ts "$(date -Is)" \
    --arg event "$event" \
    --arg detail "$detail" \
    '{ts:$ts,event:$event,detail:$detail}' >> "$EVENT_FILE"
}

emit_error() {
  local code="$1"
  local message="$2"
  local detail="${3:-}"
  local hint="${4:-Use /newtask format and include at least title or prompt.}"
  log_event "feishu_command_failed" "code=$code detail=$detail"
  jq -cn \
    --arg code "$code" \
    --arg message "$message" \
    --arg detail "$detail" \
    --arg hint "$hint" \
    --arg example "$CMD_EXAMPLE" \
    --arg replyText "Task dispatch failed: [$code] $message. $hint" \
    '{ok:false,code:$code,message:$message,detail:$detail,hint:$hint,example:$example,replyText:$replyText}'
}

require_bin jq
require_bin flock

in_array() {
  local needle="$1"
  shift
  local item
  for item in "$@"; do
    if [[ "$item" == "$needle" ]]; then
      return 0
    fi
  done
  return 1
}

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

msg_text=""
msg_file=""
start_override=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --text)
      msg_text="${2:-}"
      shift 2
      ;;
    --file)
      msg_file="${2:-}"
      shift 2
      ;;
    --start)
      start_override="${2:-}"
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

if [[ -n "$msg_file" ]]; then
  [[ -f "$msg_file" ]] || {
    echo "message file not found: $msg_file"
    exit 1
  }
  msg_text="$(cat "$msg_file")"
fi

if [[ -z "$msg_text" ]]; then
  usage
  exit 1
fi

mkdir -p "$LOCK_DIR" "$EVENT_DIR"
exec 9>"$DISPATCH_LOCK_FILE"
if ! flock -n 9; then
  emit_error "dispatcher_busy" "another /newtask dispatch is in progress" "$DISPATCH_LOCK_FILE" "Retry in a few seconds."
  exit 1
fi

default_project="internal-openclaw"
default_type="backend-feature"
default_priority="medium"
default_start="true"

if [[ -f "$INBOUND_CONFIG" ]]; then
  if ! default_project="$(jq -r '.defaultProjectId // "internal-openclaw"' "$INBOUND_CONFIG" 2>/dev/null)"; then
    emit_error "config_parse_error" "failed to parse inbound config" "$INBOUND_CONFIG"
    exit 1
  fi
  if ! default_type="$(jq -r '.defaultType // "backend-feature"' "$INBOUND_CONFIG" 2>/dev/null)"; then
    emit_error "config_parse_error" "failed to parse inbound config" "$INBOUND_CONFIG"
    exit 1
  fi
  if ! default_priority="$(jq -r '.defaultPriority // "medium"' "$INBOUND_CONFIG" 2>/dev/null)"; then
    emit_error "config_parse_error" "failed to parse inbound config" "$INBOUND_CONFIG"
    exit 1
  fi
  if ! default_start="$(jq -r '.autoStart // true' "$INBOUND_CONFIG" 2>/dev/null)"; then
    emit_error "config_parse_error" "failed to parse inbound config" "$INBOUND_CONFIG"
    exit 1
  fi
fi

project="$default_project"
task_type="$default_type"
priority="$default_priority"
task_id=""
title=""
prompt=""
start_flag="$default_start"

if [[ -n "$start_override" ]]; then
  start_flag="$start_override"
fi

first_line="$(printf '%s\n' "$msg_text" | sed -n '/./{p;q;}')"
first_line="$(trim_text "$first_line")"
if [[ ! "$first_line" =~ ^/newtask([[:space:]]|$) ]]; then
  emit_error "unsupported_command" "expected /newtask command prefix" "$first_line" "Start message with /newtask."
  exit 2
fi

while IFS= read -r line; do
  line="${line//$'\r'/}"
  [[ -z "$line" ]] && continue
  line_clean="$(trim_text "$line")"
  [[ -z "$line_clean" ]] && continue
  if [[ "$line_clean" =~ ^/newtask([[:space:]]|$) ]]; then
    continue
  fi
  if [[ "$line_clean" =~ ^([A-Za-z_]+)[[:space:]]*[:：][[:space:]]*(.*)$ ]]; then
    key="$(tr '[:upper:]' '[:lower:]' <<< "${BASH_REMATCH[1]}")"
    val="$(trim_text "${BASH_REMATCH[2]}")"
    case "$key" in
      project) project="$val" ;;
      type) task_type="$val" ;;
      priority) priority="$val" ;;
      id|task_id) task_id="$val" ;;
      title) title="$val" ;;
      start) start_flag="$val" ;;
      prompt)
        if [[ -z "$prompt" ]]; then
          prompt="$val"
        else
          prompt="$prompt"$'\n'"$val"
        fi
        ;;
      *)
        if [[ -z "$prompt" ]]; then
          prompt="$line_clean"
        else
          prompt="$prompt"$'\n'"$line_clean"
        fi
        ;;
    esac
  else
    if [[ -z "$prompt" ]]; then
      prompt="$line_clean"
    else
      prompt="$prompt"$'\n'"$line_clean"
    fi
  fi
done <<< "$msg_text"

project="$(trim_text "$project")"
task_type="$(trim_text "$task_type")"
priority="$(trim_text "$priority")"
task_id="$(trim_text "$task_id")"
title="$(trim_text "$title")"
start_flag="$(trim_text "$start_flag")"

if [[ -z "$title" ]]; then
  title="$(printf '%s\n' "$prompt" | sed -n '/./{p;q;}')"
fi
if [[ -z "$title" ]]; then
  title="feishu-task-$(date +%Y%m%d-%H%M%S)"
fi

if [[ -z "$task_id" ]]; then
  task_id="req-$(date +%Y%m%d-%H%M%S)-$(slugify "$title" | cut -c1-20)"
fi

if [[ -z "$prompt" ]]; then
  prompt="Task from Feishu command: $title"
fi

project_file="$PROJECT_DIR/$project.json"
if [[ ! -f "$project_file" ]]; then
  emit_error "invalid_project" "unknown project id" "$project" "Use a valid project id from projects/*.json."
  exit 1
fi

if ! in_array "$task_type" "${ALLOWED_TYPES[@]}"; then
  emit_error "invalid_type" "unsupported task type" "$task_type" "Allowed: backend-feature | frontend-feature | bug-fix | docs-changelog."
  exit 1
fi

if ! in_array "$priority" "${ALLOWED_PRIORITIES[@]}"; then
  emit_error "invalid_priority" "unsupported priority" "$priority" "Allowed: high | medium | low."
  exit 1
fi

start_norm="$(normalize_bool "$start_flag")"
if [[ -z "$start_norm" ]]; then
  emit_error "invalid_start" "unsupported start flag" "$start_flag" "Allowed: true|false|1|0|yes|no."
  exit 1
fi
start_flag="$start_norm"

for status_dir in active completed failed stopped archived; do
  existing="$TASK_ROOT/$status_dir/$task_id.json"
  if [[ -f "$existing" ]]; then
    emit_error "task_id_conflict" "task id already exists" "$existing" "Provide id: <new-id> or adjust title."
    exit 1
  fi
done

prompt_norm="$(tr '[:upper:]' '[:lower:]' <<< "$prompt" | awk '{gsub(/^[[:space:]]+|[[:space:]]+$/, ""); print}')"
title_norm="$(tr '[:upper:]' '[:lower:]' <<< "$title" | awk '{gsub(/^[[:space:]]+|[[:space:]]+$/, ""); print}')"
dup_id=""
shopt -s nullglob
for f in "$TASK_ROOT/active/"*.json; do
  p="$(jq -r '.projectId // empty' "$f")"
  t="$(jq -r '.title // empty' "$f" | tr '[:upper:]' '[:lower:]' | awk '{gsub(/^[[:space:]]+|[[:space:]]+$/, ""); print}')"
  pp="$(jq -r '.launch.initialPrompt // empty' "$f" | tr '[:upper:]' '[:lower:]' | awk '{gsub(/^[[:space:]]+|[[:space:]]+$/, ""); print}')"
  if [[ "$p" == "$project" && "$t" == "$title_norm" && "$pp" == "$prompt_norm" ]]; then
    dup_id="$(basename "$f" .json)"
    break
  fi
done
if [[ -n "$dup_id" ]]; then
  emit_error "duplicate_task" "similar active task already exists" "$dup_id" "Reuse existing task or change title/prompt."
  exit 1
fi

if ! create_out="$("$NEW_TASK_SCRIPT" \
  --project "$project" \
  --task-id "$task_id" \
  --title "$title" \
  --type "$task_type" \
  --priority "$priority" \
  --prompt "$prompt" 2>&1)"; then
  emit_error "task_create_failed" "new-task.sh failed" "$create_out" "Check project/type/priority values and rerun."
  exit 1
fi

start_out=""
started=false
tmux_session=""
worktree_path="$(jq -r '.worktreeRoot // "/home/ubuntu/workspace/worktrees"' "$project_file")/$task_id"
if [[ "$start_flag" == "true" ]]; then
  if ! start_out="$("$START_TASK_SCRIPT" "$task_id" 2>&1)"; then
    emit_error "task_start_failed" "start-task.sh failed after task creation" "$start_out" "Task is created. Inspect task json and run start-task manually."
    exit 1
  fi
  started=true
  if [[ "$start_out" =~ session=([^[:space:]]+) ]]; then
    tmux_session="${BASH_REMATCH[1]}"
  fi
fi

log_event "feishu_command_task_created" "task_id=$task_id project=$project type=$task_type priority=$priority started=$started"

reply_text="Task created: $task_id (project=$project, started=$started, worktree=$worktree_path)."
if [[ "$started" == "true" ]] && [[ -n "$tmux_session" ]]; then
  reply_text="Task created: $task_id (project=$project, started=$started, tmuxSession=$tmux_session, worktree=$worktree_path)."
fi

jq -cn \
  --arg taskId "$task_id" \
  --arg project "$project" \
  --arg type "$task_type" \
  --arg priority "$priority" \
  --arg title "$title" \
  --arg createOutput "$create_out" \
  --arg startOutput "$start_out" \
  --arg started "$started" \
  --arg tmuxSession "$tmux_session" \
  --arg worktreePath "$worktree_path" \
  --arg replyText "$reply_text" \
  '{ok:true,taskId:$taskId,project:$project,type:$type,priority:$priority,title:$title,started:($started=="true"),tmuxSession:($tmuxSession | if .=="" then null else . end),worktreePath:$worktreePath,createOutput:$createOutput,startOutput:$startOutput,replyText:$replyText}'
