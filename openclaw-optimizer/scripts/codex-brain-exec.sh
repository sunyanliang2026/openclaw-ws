#!/usr/bin/env bash
set -euo pipefail

if [[ -d "/home/ubuntu/.bun/bin" ]]; then
  export PATH="/home/ubuntu/.bun/bin:$PATH"
fi

usage() {
  echo "Usage: $0 --title <text> [--project <id>] [--task-id <id>] [--brain-dir <path>] [--run-root <path>] -- codex exec ..."
}

TITLE=""
PROJECT=""
TASK_ID=""
BRAIN_DIR="/home/ubuntu/brain"
RUN_ROOT="/home/ubuntu/.openclaw/workspace/openclaw-optimizer/runtime/codex-cli-runs"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --title)
      TITLE="${2:-}"
      shift 2
      ;;
    --project)
      PROJECT="${2:-}"
      shift 2
      ;;
    --task-id)
      TASK_ID="${2:-}"
      shift 2
      ;;
    --brain-dir)
      BRAIN_DIR="${2:-}"
      shift 2
      ;;
    --run-root)
      RUN_ROOT="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    *)
      echo "unknown arg: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$TITLE" ]]; then
  usage
  exit 1
fi

if [[ $# -eq 0 ]]; then
  echo "missing wrapped command" >&2
  usage
  exit 1
fi

require_bin() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing binary: $1" >&2
    exit 1
  }
}

quote_join() {
  local out=""
  local item
  for item in "$@"; do
    if [[ -n "$out" ]]; then
      out+=" "
    fi
    out+="$(printf '%q' "$item")"
  done
  printf '%s' "$out"
}

slugify() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
}

extract_workdir() {
  local -a args=("$@")
  local i=0
  while (( i < ${#args[@]} )); do
    case "${args[$i]}" in
      -C|--cd)
        if (( i + 1 < ${#args[@]} )); then
          printf '%s' "${args[$((i + 1))]}"
          return 0
        fi
        ;;
    esac
    ((i += 1))
  done

  pwd
}

extract_output_last_message_path() {
  local -a args=("$@")
  local i=0
  while (( i < ${#args[@]} )); do
    case "${args[$i]}" in
      -o|--output-last-message)
        if (( i + 1 < ${#args[@]} )); then
          printf '%s' "${args[$((i + 1))]}"
          return 0
        fi
        ;;
    esac
    ((i += 1))
  done

  return 1
}

require_bin codex
require_bin tee

mkdir -p "$RUN_ROOT"
run_id="$(date +%Y-%m-%d-%H%M%S)-$(slugify "$TITLE")"
if [[ -z "$run_id" ]]; then
  run_id="$(date +%Y-%m-%d-%H%M%S)-codex-run"
fi
run_dir="$RUN_ROOT/$run_id"
mkdir -p "$run_dir"

console_log="$run_dir/console.log"
last_message="$run_dir/last-message.txt"
closeout_body="$run_dir/closeout.md"

declare -a cmd=("$@")
declare -a wrapped_cmd=()
has_output_last_message=0

if [[ "${cmd[0]}" != "codex" ]]; then
  echo "wrapped command must start with codex" >&2
  exit 1
fi

if (( ${#cmd[@]} >= 2 )) && [[ "${cmd[1]}" == "exec" ]]; then
  for arg in "${cmd[@]}"; do
    if [[ "$arg" == "-o" || "$arg" == "--output-last-message" ]]; then
      has_output_last_message=1
      break
    fi
  done

  wrapped_cmd=("${cmd[@]}")
  if [[ "$has_output_last_message" -eq 0 ]]; then
    wrapped_cmd+=("-o" "$last_message")
  else
    existing_last_message="$(extract_output_last_message_path "${wrapped_cmd[@]}" || true)"
    if [[ -n "$existing_last_message" ]]; then
      last_message="$existing_last_message"
    fi
  fi
else
  echo "wrapped command must use 'codex exec' for automatic closeout" >&2
  exit 1
fi

workdir="$(extract_workdir "${wrapped_cmd[@]}")"
if [[ ! "$workdir" = /* ]]; then
  workdir="$(cd "$workdir" 2>/dev/null && pwd || printf '%s' "$workdir")"
fi

repo_root=""
branch=""
git_status=""
if git -C "$workdir" rev-parse --show-toplevel >/dev/null 2>&1; then
  repo_root="$(git -C "$workdir" rev-parse --show-toplevel)"
  branch="$(git -C "$workdir" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  git_status="$(git -C "$workdir" status --short --untracked-files=no 2>/dev/null || true)"
fi

cmd_string="$(quote_join "${wrapped_cmd[@]}")"
printf 'Running: %s\n' "$cmd_string"

set +e
"${wrapped_cmd[@]}" 2>&1 | tee "$console_log"
cmd_status=${PIPESTATUS[0]}
set -e

final_message=""
if [[ -f "$last_message" ]]; then
  final_message="$(cat "$last_message")"
fi

if [[ -z "$final_message" ]]; then
  final_message="$(tail -n 60 "$console_log" 2>/dev/null || true)"
fi

{
  printf 'Decision capture for direct codex exec session.\n\n'
  printf -- '- title: %s\n' "$TITLE"
  printf -- '- exitCode: %s\n' "$cmd_status"
  printf -- '- command: %s\n' "$cmd_string"
  printf -- '- workdir: %s\n' "$workdir"
  printf -- '- runDir: %s\n' "$run_dir"
  printf -- '- consoleLog: %s\n' "$console_log"
  if [[ -n "$last_message" ]]; then
    printf -- '- finalMessageFile: %s\n' "$last_message"
  fi
  if [[ -n "$repo_root" ]]; then
    printf -- '- repoRoot: %s\n' "$repo_root"
  fi
  if [[ -n "$branch" ]]; then
    printf -- '- branch: %s\n' "$branch"
  fi
  if [[ -n "$TASK_ID" ]]; then
    printf -- '- taskId: %s\n' "$TASK_ID"
  fi
  printf '\nFinal answer or closeout:\n\n%s\n' "$final_message"
  if [[ -n "$git_status" ]]; then
    printf '\nGit status snapshot:\n\n```text\n%s\n```\n' "$git_status"
  fi
} > "$closeout_body"

"/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/capture-brain-note.sh" \
  --source codex-cli \
  --title "$TITLE" \
  --body-file "$closeout_body" \
  --project "$PROJECT" \
  --task-id "$TASK_ID" \
  --origin-path "$console_log" \
  --brain-dir "$BRAIN_DIR" >/dev/null

printf 'captured closeout to brain from %s\n' "$run_dir"
exit "$cmd_status"
