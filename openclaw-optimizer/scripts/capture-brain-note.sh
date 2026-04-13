#!/usr/bin/env bash
set -euo pipefail

if [[ -d "/home/ubuntu/.bun/bin" ]]; then
  export PATH="/home/ubuntu/.bun/bin:$PATH"
fi

usage() {
  echo "Usage: $0 --source <feishu|codex-cli|manual> --title <text> [--body <text> | --body-file <path>] [--project <id>] [--task-id <id>] [--chat-id <id>] [--origin-path <path>] [--dir <relative_dir>] [--no-import]"
}

BRAIN_DIR="/home/ubuntu/brain"
SOURCE=""
TITLE=""
BODY=""
BODY_FILE=""
PROJECT=""
TASK_ID=""
CHAT_ID=""
ORIGIN_PATH=""
RELATIVE_DIR=""
IMPORT=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)
      SOURCE="${2:-}"
      shift 2
      ;;
    --title)
      TITLE="${2:-}"
      shift 2
      ;;
    --body)
      BODY="${2:-}"
      shift 2
      ;;
    --body-file)
      BODY_FILE="${2:-}"
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
    --chat-id)
      CHAT_ID="${2:-}"
      shift 2
      ;;
    --origin-path)
      ORIGIN_PATH="${2:-}"
      shift 2
      ;;
    --dir)
      RELATIVE_DIR="${2:-}"
      shift 2
      ;;
    --brain-dir)
      BRAIN_DIR="${2:-}"
      shift 2
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

slugify() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
}

append_bullet_if_present() {
  local file="$1"
  local label="$2"
  local value="$3"
  if [[ -n "$value" ]]; then
    printf -- '- %s: %s\n' "$label" "$value" >> "$file"
  fi
}

if [[ -z "$SOURCE" || -z "$TITLE" ]]; then
  usage
  exit 1
fi

if [[ -n "$BODY_FILE" ]]; then
  if [[ ! -f "$BODY_FILE" ]]; then
    echo "body file not found: $BODY_FILE" >&2
    exit 1
  fi
  BODY="$(cat "$BODY_FILE")"
elif [[ -z "$BODY" && ! -t 0 ]]; then
  BODY="$(cat)"
fi

if [[ -z "$BODY" ]]; then
  echo "note body is empty" >&2
  exit 1
fi

if [[ -z "$RELATIVE_DIR" ]]; then
  RELATIVE_DIR="inbox/$(slugify "$SOURCE")"
fi

mkdir -p "$BRAIN_DIR/$RELATIVE_DIR"

timestamp="$(date +%Y-%m-%d-%H%M%S)"
slug="$(slugify "$TITLE")"
source_slug="$(slugify "$SOURCE")"
if [[ -z "$slug" ]]; then
  slug="note"
fi

target_file="$BRAIN_DIR/$RELATIVE_DIR/$timestamp-$slug.md"
tmp="$(mktemp)"

printf -- '---\n' > "$tmp"
printf 'type: source\n' >> "$tmp"
printf 'title: "%s"\n' "$(printf '%s' "$TITLE" | sed 's/"/\\"/g')" >> "$tmp"
printf 'created: "%s"\n' "$(date -Is)" >> "$tmp"
printf 'tags:\n' >> "$tmp"
printf -- '  - capture\n' >> "$tmp"
if [[ -n "$source_slug" ]]; then
  printf '  - source-%s\n' "$source_slug" >> "$tmp"
fi
printf -- '---\n\n' >> "$tmp"
printf '# %s\n\n' "$TITLE" >> "$tmp"
printf '## Compiled Truth\n\n' >> "$tmp"
append_bullet_if_present "$tmp" "source" "$SOURCE"
append_bullet_if_present "$tmp" "capturedAt" "$(date -Is)"
append_bullet_if_present "$tmp" "project" "$PROJECT"
append_bullet_if_present "$tmp" "taskId" "$TASK_ID"
append_bullet_if_present "$tmp" "chatId" "$CHAT_ID"
append_bullet_if_present "$tmp" "originPath" "$ORIGIN_PATH"
append_bullet_if_present "$tmp" "filedAs" "$RELATIVE_DIR"

printf '\n## Summary\n\n%s\n' "$BODY" >> "$tmp"
printf '\n## Source Note\n\n- This page is a curated capture from `%s`, not a full transcript.\n' "$SOURCE" >> "$tmp"

mv "$tmp" "$target_file"

if [[ "$IMPORT" -eq 1 ]]; then
  if command -v gbrain >/dev/null 2>&1; then
    gbrain import "$BRAIN_DIR/$RELATIVE_DIR" --no-embed >/dev/null
  else
    echo "gbrain not found in PATH, skipped import for $target_file" >&2
  fi
fi

echo "captured brain note: $target_file"
