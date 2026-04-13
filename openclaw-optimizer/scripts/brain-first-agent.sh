#!/usr/bin/env bash
set -euo pipefail

if [[ -d "/home/ubuntu/.bun/bin" ]]; then
  export PATH="/home/ubuntu/.bun/bin:$PATH"
fi

usage() {
  cat <<'EOF'
Usage: brain-first-agent.sh --message <text>|--message-file <path> [options]

Options:
  --agent <id>               Forward to openclaw agent --agent
  --session-id <id>          Forward to openclaw agent --session-id
  --channel <name>           Forward to openclaw agent --channel
  --to <target>              Forward to openclaw agent --to
  --deliver                  Forward to openclaw agent --deliver
  --reply-channel <name>     Forward to openclaw agent --reply-channel
  --reply-to <target>        Forward to openclaw agent --reply-to
  --reply-account <id>       Forward to openclaw agent --reply-account
  --thinking <level>         Forward to openclaw agent --thinking
  --timeout <seconds>        Forward to openclaw agent --timeout
  --verbose <on|off>         Forward to openclaw agent --verbose
  --local                    Forward to openclaw agent --local
  --expand                   Allow gbrain ask to expand query terms
  --context-only             Print collected brain context only; do not call openclaw agent
  --json                     Emit JSON output
  -h, --help                 Show help
EOF
}

MESSAGE_TEXT=""
MESSAGE_FILE=""
AGENT_ID=""
SESSION_ID=""
CHANNEL=""
TO_TARGET=""
DELIVER=0
REPLY_CHANNEL=""
REPLY_TO=""
REPLY_ACCOUNT=""
THINKING=""
TIMEOUT_SECONDS=""
VERBOSE_LEVEL=""
LOCAL_MODE=0
ALLOW_EXPAND=0
CONTEXT_ONLY=0
JSON_OUTPUT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --message)
      MESSAGE_TEXT="${2:-}"
      shift 2
      ;;
    --message-file)
      MESSAGE_FILE="${2:-}"
      shift 2
      ;;
    --agent)
      AGENT_ID="${2:-}"
      shift 2
      ;;
    --session-id)
      SESSION_ID="${2:-}"
      shift 2
      ;;
    --channel)
      CHANNEL="${2:-}"
      shift 2
      ;;
    --to)
      TO_TARGET="${2:-}"
      shift 2
      ;;
    --deliver)
      DELIVER=1
      shift
      ;;
    --reply-channel)
      REPLY_CHANNEL="${2:-}"
      shift 2
      ;;
    --reply-to)
      REPLY_TO="${2:-}"
      shift 2
      ;;
    --reply-account)
      REPLY_ACCOUNT="${2:-}"
      shift 2
      ;;
    --thinking)
      THINKING="${2:-}"
      shift 2
      ;;
    --timeout)
      TIMEOUT_SECONDS="${2:-}"
      shift 2
      ;;
    --verbose)
      VERBOSE_LEVEL="${2:-}"
      shift 2
      ;;
    --local)
      LOCAL_MODE=1
      shift
      ;;
    --expand)
      ALLOW_EXPAND=1
      shift
      ;;
    --context-only)
      CONTEXT_ONLY=1
      shift
      ;;
    --json)
      JSON_OUTPUT=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown arg: $1" >&2
      usage
      exit 1
      ;;
  esac
done

require_bin() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing binary: $1" >&2
    exit 1
  }
}

trim_text() {
  local value="$1"
  value="$(printf '%s' "$value" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  printf '%s' "$value"
}

build_keyword_query() {
  local value="$1"
  value="$(printf '%s' "$value" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/ /g' \
    | tr ' ' '\n' \
    | awk 'length($0) >= 4' \
    | awk '!seen[$0]++' \
    | grep -Ev '^(what|when|where|which|have|with|this|that|from|into|about|did|does|they|them|your|ours|were|been|then|than|will|would|should|could|there|here|auto)$' \
    | head -n 6 \
    | tr '\n' ' ')"
  value="$(trim_text "$value")"
  printf '%s' "$value"
}

tail_keyword_query() {
  local value="$1"
  value="$(printf '%s' "$value" | tr ' ' '\n' | tail -n 2 | tr '\n' ' ')"
  value="$(trim_text "$value")"
  printf '%s' "$value"
}

load_text_arg() {
  local current="$1"
  local file_path="$2"
  if [[ -n "$file_path" ]]; then
    if [[ ! -f "$file_path" ]]; then
      echo "file not found: $file_path" >&2
      exit 1
    fi
    cat "$file_path"
    return 0
  fi
  printf '%s' "$current"
}

truncate_lines() {
  local value="$1"
  local limit="${2:-40}"
  printf '%s\n' "$value" | sed -n "1,${limit}p"
}

require_bin gbrain
require_bin openclaw
require_bin jq

MESSAGE_TEXT="$(load_text_arg "$MESSAGE_TEXT" "$MESSAGE_FILE")"
MESSAGE_TEXT="$(trim_text "$MESSAGE_TEXT")"

if [[ -z "$MESSAGE_TEXT" ]]; then
  usage
  exit 1
fi

gbrain_ask_cmd=(gbrain ask "$MESSAGE_TEXT")
if [[ "$ALLOW_EXPAND" -eq 0 ]]; then
  gbrain_ask_cmd+=(--no-expand)
fi

brain_answer="$("${gbrain_ask_cmd[@]}" 2>/dev/null || true)"
brain_search="$(gbrain search "$MESSAGE_TEXT" 2>/dev/null || true)"

keyword_query="$(build_keyword_query "$MESSAGE_TEXT")"
if [[ -n "$keyword_query" ]]; then
  if [[ -z "$brain_answer" || "$brain_answer" == "No results." ]]; then
    keyword_answer="$(gbrain ask "$keyword_query" --no-expand 2>/dev/null || true)"
    if [[ -n "$keyword_answer" && "$keyword_answer" != "No results." ]]; then
      brain_answer="$keyword_answer"
    fi
  fi
  if [[ -z "$brain_search" || "$brain_search" == "No results." ]]; then
    keyword_search="$(gbrain search "$keyword_query" 2>/dev/null || true)"
    if [[ -n "$keyword_search" && "$keyword_search" != "No results." ]]; then
      brain_search="$keyword_search"
    fi
  fi
  tail_query="$(tail_keyword_query "$keyword_query")"
  if [[ -n "$tail_query" && "$tail_query" != "$keyword_query" ]]; then
    if [[ -z "$brain_answer" || "$brain_answer" == "No results." ]]; then
      tail_answer="$(gbrain ask "$tail_query" --no-expand 2>/dev/null || true)"
      if [[ -n "$tail_answer" && "$tail_answer" != "No results." ]]; then
        brain_answer="$tail_answer"
      fi
    fi
    if [[ -z "$brain_search" || "$brain_search" == "No results." ]]; then
      tail_search="$(gbrain search "$tail_query" 2>/dev/null || true)"
      if [[ -n "$tail_search" && "$tail_search" != "No results." ]]; then
        brain_search="$tail_search"
      fi
    fi
  fi
fi

brain_answer="$(truncate_lines "$brain_answer" 80)"
brain_search="$(truncate_lines "$brain_search" 20)"

if [[ -z "$brain_answer" ]]; then
  brain_answer="No gbrain answer returned."
fi

if [[ -z "$brain_search" ]]; then
  brain_search="No matching gbrain pages found."
fi

prompt_file="$(mktemp)"
{
  printf 'Brain-first instruction:\n'
  printf '1. Treat the gbrain context below as the first retrieval layer.\n'
  printf '2. If it already answers the request, answer from it directly and mention the relevant note or slug.\n'
  printf '3. If it is incomplete, say what is missing, then use workspace/runtime knowledge.\n'
  printf '4. Do not ignore the gbrain context.\n\n'
  printf 'User request:\n%s\n\n' "$MESSAGE_TEXT"
  printf 'gbrain ask:\n%s\n\n' "$brain_answer"
  printf 'gbrain search:\n%s\n' "$brain_search"
} > "$prompt_file"

if [[ "$CONTEXT_ONLY" -eq 1 ]]; then
  if [[ "$JSON_OUTPUT" -eq 1 ]]; then
    jq -n \
      --arg message "$MESSAGE_TEXT" \
      --arg brainAsk "$brain_answer" \
      --arg brainSearch "$brain_search" \
      --arg composedPrompt "$(cat "$prompt_file")" \
      '{message:$message,brainAsk:$brainAsk,brainSearch:$brainSearch,composedPrompt:$composedPrompt}'
  else
    cat "$prompt_file"
  fi
  rm -f "$prompt_file"
  exit 0
fi

agent_cmd=(openclaw agent --message "$(cat "$prompt_file")")
if [[ -n "$AGENT_ID" ]]; then
  agent_cmd+=(--agent "$AGENT_ID")
fi
if [[ -n "$SESSION_ID" ]]; then
  agent_cmd+=(--session-id "$SESSION_ID")
fi
if [[ -n "$CHANNEL" ]]; then
  agent_cmd+=(--channel "$CHANNEL")
fi
if [[ -n "$TO_TARGET" ]]; then
  agent_cmd+=(--to "$TO_TARGET")
fi
if [[ "$DELIVER" -eq 1 ]]; then
  agent_cmd+=(--deliver)
fi
if [[ -n "$REPLY_CHANNEL" ]]; then
  agent_cmd+=(--reply-channel "$REPLY_CHANNEL")
fi
if [[ -n "$REPLY_TO" ]]; then
  agent_cmd+=(--reply-to "$REPLY_TO")
fi
if [[ -n "$REPLY_ACCOUNT" ]]; then
  agent_cmd+=(--reply-account "$REPLY_ACCOUNT")
fi
if [[ -n "$THINKING" ]]; then
  agent_cmd+=(--thinking "$THINKING")
fi
if [[ -n "$TIMEOUT_SECONDS" ]]; then
  agent_cmd+=(--timeout "$TIMEOUT_SECONDS")
fi
if [[ -n "$VERBOSE_LEVEL" ]]; then
  agent_cmd+=(--verbose "$VERBOSE_LEVEL")
fi
if [[ "$LOCAL_MODE" -eq 1 ]]; then
  agent_cmd+=(--local)
fi

if [[ "$JSON_OUTPUT" -eq 1 ]]; then
  agent_json="$(mktemp)"
  "${agent_cmd[@]}" --json > "$agent_json"
  jq -n \
    --arg message "$MESSAGE_TEXT" \
    --arg brainAsk "$brain_answer" \
    --arg brainSearch "$brain_search" \
    --arg composedPrompt "$(cat "$prompt_file")" \
    --slurpfile agent "$agent_json" \
    '{message:$message,brainAsk:$brainAsk,brainSearch:$brainSearch,composedPrompt:$composedPrompt,agent:$agent[0]}'
  rm -f "$agent_json"
else
  "${agent_cmd[@]}"
fi

rm -f "$prompt_file"
