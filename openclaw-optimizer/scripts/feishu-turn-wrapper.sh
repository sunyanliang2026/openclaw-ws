#!/usr/bin/env bash
set -euo pipefail

if [[ -d "/home/ubuntu/.bun/bin" ]]; then
  export PATH="/home/ubuntu/.bun/bin:$PATH"
fi

usage() {
  echo "Usage: $0 --message <text>|--message-file <path> --chat-id <oc_xxx> [--session-id <id>] [--project <id>] [--agent <id>] [--reply-account <id>] [--thinking <level>] [--brain-dir <path>] [--deliver 0|1] [--capture 0|1] [--capture-summary <text>] [--durable-type <type>] [--json]"
}

MESSAGE_TEXT=""
MESSAGE_FILE=""
CHAT_ID=""
SESSION_ID=""
PROJECT="internal-openclaw"
AGENT_ID="main"
REPLY_ACCOUNT=""
THINKING=""
BRAIN_DIR="/home/ubuntu/brain"
DELIVER=1
CAPTURE=1
CAPTURE_SUMMARY=""
DURABLE_TYPE="general"
JSON_OUTPUT=0

ROOT="/home/ubuntu/.openclaw/workspace/openclaw-optimizer/runtime"
DISPATCH_SCRIPT="/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/feishu-command-dispatch.sh"
CAPTURE_SCRIPT="/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/capture-feishu-turn-to-brain.sh"
EVENT_DIR="$ROOT/events"

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
    --chat-id)
      CHAT_ID="${2:-}"
      shift 2
      ;;
    --session-id)
      SESSION_ID="${2:-}"
      shift 2
      ;;
    --project)
      PROJECT="${2:-}"
      shift 2
      ;;
    --agent)
      AGENT_ID="${2:-}"
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
    --brain-dir)
      BRAIN_DIR="${2:-}"
      shift 2
      ;;
    --deliver)
      DELIVER="${2:-1}"
      shift 2
      ;;
    --capture)
      CAPTURE="${2:-1}"
      shift 2
      ;;
    --capture-summary)
      CAPTURE_SUMMARY="${2:-}"
      shift 2
      ;;
    --durable-type)
      DURABLE_TYPE="${2:-general}"
      shift 2
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

resolve_session_id() {
  local chat_id="$1"
  local agent_id="$2"
  openclaw status --json \
    | jq -r --arg chat "$chat_id" --arg agent "$agent_id" '
        .sessions.recent
        | map(select(.agentId == $agent and (.key | test("feishu:group:" + $chat + "$"))))
        | sort_by(.updatedAt)
        | last
        | .sessionId // empty
      '
}

extract_reply_text() {
  local json_file="$1"
  jq -r '
    .result.payloads
    | map(select(.text != null and .text != ""))
    | map(.text)
    | join("\n\n")
  ' "$json_file"
}

emit_json() {
  local json_file="$1"
  jq -c '.' "$json_file"
}

log_event() {
  local event="$1"
  local status="$2"
  local detail="$3"
  local event_file="$EVENT_DIR/feishu-turn-wrapper-events-$(date +%Y%m%d).jsonl"
  mkdir -p "$EVENT_DIR"
  jq -nc \
    --arg ts "$(date -Is)" \
    --arg event "$event" \
    --arg status "$status" \
    --arg detail "$detail" \
    --arg chatId "$CHAT_ID" \
    --arg sessionId "$SESSION_ID" \
    '{ts:$ts,event:$event,status:$status,detail:$detail,chatId:$chatId,sessionId:(if $sessionId=="" then null else $sessionId end)}' \
    >> "$event_file"
}

require_bin jq
require_bin openclaw

MESSAGE_TEXT="$(load_text_arg "$MESSAGE_TEXT" "$MESSAGE_FILE")"
MESSAGE_TEXT="$(trim_text "$MESSAGE_TEXT")"
CHAT_ID="${CHAT_ID#chat:}"

if [[ -z "$MESSAGE_TEXT" || -z "$CHAT_ID" ]]; then
  usage
  exit 1
fi

if [[ "$MESSAGE_TEXT" =~ ^/newtask([[:space:]]|$) ]]; then
  dispatch_json="$(mktemp)"
  "$DISPATCH_SCRIPT" --text "$MESSAGE_TEXT" --chat-id "$CHAT_ID" > "$dispatch_json"
  reply_text="$(jq -r '.replyText // .message // "Task dispatch finished."' "$dispatch_json")"

  send_json="$(mktemp)"
  if [[ "$DELIVER" == "1" ]]; then
    send_args=(openclaw message send --channel feishu --target "$CHAT_ID" --message "$reply_text" --json)
    if [[ -n "$REPLY_ACCOUNT" ]]; then
      send_args+=(--account "$REPLY_ACCOUNT")
    fi
    "${send_args[@]}" > "$send_json"
    log_event "dispatch_reply" "sent" "$reply_text"
  else
    jq -nc --arg reply "$reply_text" '{delivery:"skipped",replyText:$reply}' > "$send_json"
    log_event "dispatch_reply" "skipped" "$reply_text"
  fi

  result_json="$(mktemp)"
  jq -n \
    --slurpfile dispatch "$dispatch_json" \
    --slurpfile delivery "$send_json" \
    '{mode:"newtask",dispatch:$dispatch[0],delivery:$delivery[0]}' > "$result_json"

  if [[ "$JSON_OUTPUT" == "1" ]]; then
    emit_json "$result_json"
  else
    jq -r '.dispatch.replyText' "$result_json"
  fi
  exit 0
fi

if [[ -z "$SESSION_ID" ]]; then
  SESSION_ID="$(resolve_session_id "$CHAT_ID" "$AGENT_ID")"
fi

if [[ -z "$SESSION_ID" ]]; then
  echo "unable to resolve session id for chat: $CHAT_ID" >&2
  exit 1
fi

agent_json="$(mktemp)"
agent_args=(openclaw agent --session-id "$SESSION_ID" --message "$MESSAGE_TEXT" --json)
if [[ -n "$THINKING" ]]; then
  agent_args+=(--thinking "$THINKING")
fi
"${agent_args[@]}" > "$agent_json"

reply_text="$(extract_reply_text "$agent_json")"
if [[ -z "$reply_text" ]]; then
  echo "agent returned empty reply payload" >&2
  exit 1
fi

delivery_json="$(mktemp)"
if [[ "$DELIVER" == "1" ]]; then
  send_args=(openclaw message send --channel feishu --target "$CHAT_ID" --message "$reply_text" --json)
  if [[ -n "$REPLY_ACCOUNT" ]]; then
    send_args+=(--account "$REPLY_ACCOUNT")
  fi
  "${send_args[@]}" > "$delivery_json"
  log_event "feishu_reply" "sent" "$(printf '%s' "$reply_text" | head -c 200)"
else
  jq -nc --arg reply "$reply_text" '{delivery:"skipped",replyText:$reply}' > "$delivery_json"
  log_event "feishu_reply" "skipped" "$(printf '%s' "$reply_text" | head -c 200)"
fi

capture_json="$(mktemp)"
if [[ "$CAPTURE" == "1" ]]; then
  capture_args=("$CAPTURE_SCRIPT" --message "$MESSAGE_TEXT" --reply "$reply_text" --chat-id "$CHAT_ID" --project "$PROJECT" --durable-type "$DURABLE_TYPE")
  capture_args+=(--brain-dir "$BRAIN_DIR")
  if [[ -n "$CAPTURE_SUMMARY" ]]; then
    capture_args+=(--summary "$CAPTURE_SUMMARY")
  fi
  capture_output="$("${capture_args[@]}" 2>&1 || true)"
  jq -nc --arg output "$capture_output" '{captureOutput:$output}' > "$capture_json"
  log_event "feishu_capture" "done" "$capture_output"
else
  jq -nc '{captureOutput:"capture disabled"}' > "$capture_json"
  log_event "feishu_capture" "skipped" "capture disabled"
fi

result_json="$(mktemp)"
jq -n \
  --arg mode "chat" \
  --arg chatId "$CHAT_ID" \
  --arg sessionId "$SESSION_ID" \
  --arg replyText "$reply_text" \
  --slurpfile agent "$agent_json" \
  --slurpfile delivery "$delivery_json" \
  --slurpfile capture "$capture_json" \
  '{
    mode:$mode,
    chatId:$chatId,
    sessionId:$sessionId,
    replyText:$replyText,
    agent:$agent[0],
    delivery:$delivery[0],
    capture:$capture[0]
  }' > "$result_json"

if [[ "$JSON_OUTPUT" == "1" ]]; then
  emit_json "$result_json"
else
  printf '%s\n' "$reply_text"
fi
