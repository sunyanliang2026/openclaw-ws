#!/usr/bin/env bash
set -euo pipefail

if [[ -d "/home/ubuntu/.bun/bin" ]]; then
  export PATH="/home/ubuntu/.bun/bin:$PATH"
fi

usage() {
  echo "Usage: $0 [--message <text> | --message-file <path>] [--reply <text> | --reply-file <path>] [--summary <text> | --summary-file <path>] [--title <text>] [--chat-id <id>] [--project <id>] [--durable-type <decision|fact|preference|follow-up|general>] [--force] [--brain-dir <path>] [--no-import]"
}

ROOT="/home/ubuntu/.openclaw/workspace/openclaw-optimizer/runtime"
BRAIN_DIR="/home/ubuntu/brain"
MESSAGE_TEXT=""
MESSAGE_FILE=""
REPLY_TEXT=""
REPLY_FILE=""
SUMMARY_TEXT=""
SUMMARY_FILE=""
TITLE=""
CHAT_ID=""
PROJECT=""
DURABLE_TYPE="general"
FORCE=0
IMPORT=1

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
    --reply)
      REPLY_TEXT="${2:-}"
      shift 2
      ;;
    --reply-file)
      REPLY_FILE="${2:-}"
      shift 2
      ;;
    --summary)
      SUMMARY_TEXT="${2:-}"
      shift 2
      ;;
    --summary-file)
      SUMMARY_FILE="${2:-}"
      shift 2
      ;;
    --title)
      TITLE="${2:-}"
      shift 2
      ;;
    --chat-id)
      CHAT_ID="${2:-}"
      shift 2
      ;;
    --project)
      PROJECT="${2:-}"
      shift 2
      ;;
    --durable-type)
      DURABLE_TYPE="${2:-}"
      shift 2
      ;;
    --brain-dir)
      BRAIN_DIR="${2:-}"
      shift 2
      ;;
    --force)
      FORCE=1
      shift
      ;;
    --no-import)
      IMPORT=0
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
  value="$(printf '%s' "$value" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')"
  printf '%s' "$value"
}

first_nonempty_line() {
  printf '%s\n' "$1" | sed -n '/[^[:space:]]/ { s/^[[:space:]]*//; p; q; }'
}

truncate_text() {
  local value="$1"
  local limit="${2:-280}"
  if (( ${#value} <= limit )); then
    printf '%s' "$value"
  else
    printf '%s...' "${value:0:limit}"
  fi
}

slugify() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
}

log_event() {
  local status="$1"
  local reason="$2"
  local event_dir="$ROOT/events"
  local event_file="$event_dir/feishu-brain-events-$(date +%Y%m%d).jsonl"
  mkdir -p "$event_dir"
  jq -nc \
    --arg ts "$(date -Is)" \
    --arg status "$status" \
    --arg reason "$reason" \
    --arg chatId "$CHAT_ID" \
    --arg title "$TITLE" \
    --arg durableType "$DURABLE_TYPE" \
    '{ts:$ts,status:$status,reason:$reason,chatId:(if $chatId=="" then null else $chatId end),title:(if $title=="" then null else $title end),durableType:$durableType}' \
    >> "$event_file"
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

require_bin jq

MESSAGE_TEXT="$(load_text_arg "$MESSAGE_TEXT" "$MESSAGE_FILE")"
REPLY_TEXT="$(load_text_arg "$REPLY_TEXT" "$REPLY_FILE")"
SUMMARY_TEXT="$(load_text_arg "$SUMMARY_TEXT" "$SUMMARY_FILE")"

message_clean="$(trim_text "$MESSAGE_TEXT")"
reply_clean="$(trim_text "$REPLY_TEXT")"
summary_clean="$(trim_text "$SUMMARY_TEXT")"
message_first_line="$(first_nonempty_line "$MESSAGE_TEXT")"

if [[ "$FORCE" -eq 0 ]]; then
  if [[ -z "$message_clean" && -z "$summary_clean" ]]; then
    log_event "skipped" "empty_input"
    echo "skipped: empty input"
    exit 0
  fi

  if [[ "$message_first_line" =~ ^/newtask([[:space:]]|$) ]]; then
    log_event "skipped" "newtask_command"
    echo "skipped: /newtask handled elsewhere"
    exit 0
  fi

  if [[ "$message_clean" == "HEARTBEAT_OK" ]] || [[ "$message_clean" == Read\ HEARTBEAT.md* ]]; then
    log_event "skipped" "heartbeat"
    echo "skipped: heartbeat"
    exit 0
  fi

  if [[ -z "$summary_clean" ]]; then
    if [[ ${#message_clean} -lt 24 && ${#reply_clean} -lt 24 ]]; then
      log_event "skipped" "too_short"
      echo "skipped: no durable signal"
      exit 0
    fi

    case "$reply_clean" in
      HEARTBEAT_OK|ok|OK|好的|收到|知道了|明白|嗯嗯)
        log_event "skipped" "ack_only"
        echo "skipped: acknowledgement only"
        exit 0
        ;;
    esac
  fi
fi

if [[ -z "$TITLE" ]]; then
  TITLE="$(truncate_text "$(trim_text "$message_first_line")" 72)"
fi

if [[ -z "$TITLE" ]]; then
  TITLE="Feishu turn capture $(date +%Y-%m-%d-%H%M%S)"
fi

if [[ -z "$summary_clean" ]]; then
  summary_clean="Durable signal captured from a Feishu Q&A turn."
fi

tmp_body="$(mktemp)"
{
  printf 'Curated Feishu Q&A capture.\n\n'
  printf -- '- durableType: %s\n' "$DURABLE_TYPE"
  if [[ -n "$CHAT_ID" ]]; then
    printf -- '- chatId: %s\n' "$CHAT_ID"
  fi
  if [[ -n "$PROJECT" ]]; then
    printf -- '- project: %s\n' "$PROJECT"
  fi
  printf '\nSummary:\n\n%s\n' "$summary_clean"

  if [[ -n "$message_clean" ]]; then
    printf '\nQuestion excerpt:\n\n```text\n%s\n```\n' "$(truncate_text "$message_clean" 600)"
  fi
  if [[ -n "$reply_clean" ]]; then
    printf '\nReply excerpt:\n\n```text\n%s\n```\n' "$(truncate_text "$reply_clean" 600)"
  fi
  printf '\nNote:\n\n- This is a curated memory capture from Feishu, not a full transcript.\n'
} > "$tmp_body"

capture_args=(
  /home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/capture-brain-note.sh
  --source feishu
  --title "$TITLE"
  --body-file "$tmp_body"
  --dir "inbox/feishu"
  --brain-dir "$BRAIN_DIR"
)

if [[ -n "$PROJECT" ]]; then
  capture_args+=(--project "$PROJECT")
fi

if [[ -n "$CHAT_ID" ]]; then
  capture_args+=(--chat-id "$CHAT_ID")
fi

if [[ "$IMPORT" -eq 0 ]]; then
  capture_args+=(--no-import)
fi

"${capture_args[@]}" >/dev/null
rm -f "$tmp_body"

log_event "captured" "ok"
echo "captured feishu turn to brain: $TITLE"
