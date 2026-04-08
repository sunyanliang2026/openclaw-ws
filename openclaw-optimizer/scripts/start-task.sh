#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 [--dry-run] <task_id> [runtime_root]"
}

DRY_RUN=0
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=1
  shift
fi

TASK_ID="${1:-}"
ROOT="${2:-/home/ubuntu/.openclaw/workspace/openclaw-optimizer/runtime}"
CONCURRENCY_CONFIG="${CONCURRENCY_CONFIG:-/home/ubuntu/.openclaw/workspace/openclaw-optimizer/config/concurrency.json}"
AGENT_CONFIG_DIR="${AGENT_CONFIG_DIR:-/home/ubuntu/.openclaw/workspace/openclaw-optimizer/config/agents}"
LOG_DIR="$ROOT/logs"
LOCK_DIR="$ROOT/locks"
EVENT_DIR="$ROOT/events"
EVENT_FILE="$EVENT_DIR/start-task-events-$(date +%Y%m%d).jsonl"
RUN_DIR="$ROOT/task-runs/$TASK_ID"
RUN_LOG="$RUN_DIR/run.log"
RUN_EXIT_FILE="$RUN_DIR/exit.json"
RUN_WRAPPER="$RUN_DIR/launch.sh"

if [[ -z "$TASK_ID" ]]; then
  usage
  exit 1
fi

TASK_FILE="$ROOT/tasks/active/$TASK_ID.json"
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
require_bin git
require_bin tmux
require_bin flock

mkdir -p "$LOG_DIR" "$LOCK_DIR" "$EVENT_DIR"

log_event() {
  local event="$1"
  local detail="${2:-}"
  jq -cn \
    --arg ts "$(date -Is)" \
    --arg event "$event" \
    --arg task "$TASK_ID" \
    --arg detail "$detail" \
    '{ts:$ts,event:$event,taskId:$task,detail:$detail}' >> "$EVENT_FILE"
}

LOCK_FILE="$LOCK_DIR/start-task-$TASK_ID.lock"
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  log_event "task_start_skipped_locked" "lock=$LOCK_FILE"
  echo "start-task skipped (locked): $TASK_ID"
  exit 0
fi

repo_path="$(jq -r '.repoPath // empty' "$TASK_FILE")"
branch="$(jq -r '.branch // empty' "$TASK_FILE")"
worktree_path="$(jq -r '.worktreePath // empty' "$TASK_FILE")"
agent="$(jq -r '.agent // "codex"' "$TASK_FILE")"
status="$(jq -r '.status // "pending"' "$TASK_FILE")"
tmux_session="$(jq -r '.tmuxSession // empty' "$TASK_FILE")"
launch_cmd="$(jq -r '.launch.command // empty' "$TASK_FILE")"
initial_prompt="$(jq -r '.launch.initialPrompt // empty' "$TASK_FILE")"

if [[ -z "$repo_path" || -z "$branch" || -z "$worktree_path" ]]; then
  echo "task missing required fields: repoPath/branch/worktreePath"
  exit 1
fi

if [[ -z "$tmux_session" ]]; then
  tmux_session="agent-$TASK_ID"
fi

max_concurrent_agents=3
if [[ -f "$CONCURRENCY_CONFIG" ]]; then
  max_concurrent_agents="$(jq -r '.limits.maxConcurrentAgents // 3' "$CONCURRENCY_CONFIG")"
fi

if [[ -z "$launch_cmd" ]]; then
  agent_profile="$AGENT_CONFIG_DIR/$agent.json"
  if [[ -f "$agent_profile" ]]; then
    launch_cmd="$(jq -r '.launch.command // empty' "$agent_profile")"
  fi
fi

if [[ -z "$launch_cmd" ]]; then
  case "$agent" in
    codex)
      launch_cmd="codex exec --dangerously-bypass-approvals-and-sandbox"
      ;;
    *)
      launch_cmd="bash -lc 'echo Please set .launch.command in $TASK_FILE; sleep 5'"
      ;;
  esac
fi

launch_cmd="${launch_cmd//'{{task_id}}'/$TASK_ID}"
launch_cmd="${launch_cmd//'{{branch}}'/$branch}"
launch_cmd="${launch_cmd//'{{worktree}}'/$worktree_path}"

if [[ -n "$initial_prompt" && "$launch_cmd" == *"{{prompt}}"* ]]; then
  quoted_prompt="$(printf '%q' "$initial_prompt")"
  launch_cmd="${launch_cmd//'{{prompt}}'/$quoted_prompt}"
  initial_prompt=""
fi

if [[ -n "$initial_prompt" ]] && [[ "$launch_cmd" =~ ^codex([[:space:]]|$) ]]; then
  quoted_prompt="$(printf '%q' "$initial_prompt")"
  if [[ "$launch_cmd" =~ ^codex([[:space:]]|$) ]] && [[ ! "$launch_cmd" =~ [[:space:]]exec([[:space:]]|$) ]]; then
    launch_cmd="codex exec --dangerously-bypass-approvals-and-sandbox $quoted_prompt"
    initial_prompt=""
  elif [[ "$launch_cmd" =~ ^codex[[:space:]]+exec([[:space:]]|$) ]]; then
    launch_cmd="$launch_cmd $quoted_prompt"
    initial_prompt=""
  fi
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "dry-run"
  echo "task=$TASK_ID status=$status"
  echo "repo=$repo_path"
  echo "branch=$branch"
  echo "worktree=$worktree_path"
  echo "tmux_session=$tmux_session"
  echo "launch_cmd=$launch_cmd"
  echo "run_log=$RUN_LOG"
  echo "run_exit_file=$RUN_EXIT_FILE"
  echo "max_concurrent_agents=$max_concurrent_agents"
  exit 0
fi

if [[ ! -e "$repo_path/.git" ]]; then
  echo "repoPath is not a git repo: $repo_path"
  exit 1
fi

alive_sessions=0
shopt -s nullglob
for f in "$ROOT/tasks/active/"*.json; do
  s="$(jq -r '.tmuxSession // empty' "$f")"
  [[ -z "$s" || "$s" == "$tmux_session" ]] && continue
  if tmux has-session -t "$s" 2>/dev/null; then
    alive_sessions=$((alive_sessions + 1))
  fi
done

if ! tmux has-session -t "$tmux_session" 2>/dev/null && (( alive_sessions >= max_concurrent_agents )); then
  tmp="$(mktemp)"
  jq \
    --arg now "$(date -Is)" \
    --arg reason "concurrency_limit" \
    '.status = "queued"
    | .updatedAt = $now
    | .queuedAt = (.queuedAt // $now)
    | .queueReason = $reason' \
    "$TASK_FILE" > "$tmp"
  mv "$tmp" "$TASK_FILE"
  log_event "task_queued" "reason=concurrency_limit alive_sessions=$alive_sessions max=$max_concurrent_agents"
  echo "queued task=$TASK_ID reason=concurrency_limit alive_sessions=$alive_sessions max=$max_concurrent_agents"
  exit 0
fi

mkdir -p "$(dirname "$worktree_path")"

if ! git -C "$repo_path" worktree list --porcelain | awk '/^worktree / {print $2}' | grep -Fxq "$worktree_path"; then
  git -C "$repo_path" fetch origin >/dev/null 2>&1 || true
  if git -C "$repo_path" show-ref --verify --quiet "refs/heads/$branch"; then
    git -C "$repo_path" worktree add "$worktree_path" "$branch"
  elif git -C "$repo_path" ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1; then
    git -C "$repo_path" worktree add -b "$branch" "$worktree_path" "origin/$branch"
  else
    git -C "$repo_path" worktree add -b "$branch" "$worktree_path" "origin/main"
  fi
fi

mkdir -p "$RUN_DIR"
rm -f "$RUN_EXIT_FILE"
touch "$RUN_LOG"

launch_cmd_escaped="$(printf '%q' "$launch_cmd")"
run_log_escaped="$(printf '%q' "$RUN_LOG")"
run_exit_escaped="$(printf '%q' "$RUN_EXIT_FILE")"
run_wrapper_escaped="$(printf '%q' "$RUN_WRAPPER")"

cat > "$RUN_WRAPPER" <<EOF
#!/usr/bin/env bash
set -euo pipefail
set -o pipefail
cd "$worktree_path"
bash -lc $launch_cmd_escaped 2>&1 | tee -a $run_log_escaped
exit_code=\${PIPESTATUS[0]}
jq -cn \\
  --arg ts "\$(date -Is)" \\
  --argjson exitCode "\$exit_code" \\
  --arg cmd "$launch_cmd" \\
  '{finishedAt:\$ts,exitCode:\$exitCode,command:\$cmd}' > $run_exit_escaped
exit "\$exit_code"
EOF
chmod +x "$RUN_WRAPPER"

if tmux has-session -t "$tmux_session" 2>/dev/null; then
  log_event "tmux_exists" "session=$tmux_session"
  echo "tmux session already exists: $tmux_session"
else
  tmux new-session -d -s "$tmux_session" -c "$worktree_path" "bash $run_wrapper_escaped"
  if [[ -n "$initial_prompt" ]]; then
    tmux send-keys -t "$tmux_session" "$initial_prompt" Enter
  fi
  log_event "task_started" "session=$tmux_session worktree=$worktree_path runLog=$RUN_LOG"
fi

tmp="$(mktemp)"
jq \
  --arg status "running" \
  --arg session "$tmux_session" \
  --arg now "$(date -Is)" \
  '.status = $status
  | .tmuxSession = $session
  | .startedAt = (.startedAt // $now)
  | .updatedAt = $now
  | .queueReason = null
  | .queuedAt = null
  | .nextRetryAtEpoch = null' \
  "$TASK_FILE" > "$tmp"
mv "$tmp" "$TASK_FILE"

echo "started task=$TASK_ID session=$tmux_session"
