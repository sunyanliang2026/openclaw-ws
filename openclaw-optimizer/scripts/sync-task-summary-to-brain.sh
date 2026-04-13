#!/usr/bin/env bash
set -euo pipefail

if [[ -d "/home/ubuntu/.bun/bin" ]]; then
  export PATH="/home/ubuntu/.bun/bin:$PATH"
fi

usage() {
  echo "Usage: $0 [--summary-file <path> | --all] [--brain-dir <path>] [--force] [--no-import] [runtime_root]"
}

ROOT="/home/ubuntu/.openclaw/workspace/openclaw-optimizer/runtime"
BRAIN_DIR="/home/ubuntu/brain"
SUMMARY_FILE=""
SYNC_ALL=0
FORCE=0
IMPORT=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --summary-file)
      SUMMARY_FILE="${2:-}"
      shift 2
      ;;
    --all)
      SYNC_ALL=1
      shift
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
      ROOT="$1"
      shift
      ;;
  esac
done

require_bin() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing binary: $1" >&2
    exit 1
  }
}

slugify() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
}

extract_from_evidence() {
  local label="$1"
  local evidence="$2"
  printf '%s\n' "$evidence" \
    | sed -n "s/^[- ]*${label}:[[:space:]]*//p" \
    | head -n 1
}

append_bullet_if_present() {
  local file="$1"
  local label="$2"
  local value="$3"
  if [[ -n "$value" && "$value" != "null" ]]; then
    printf -- '- %s: %s\n' "$label" "$value" >> "$file"
  fi
}

write_section_block() {
  local file="$1"
  local title="$2"
  local body="$3"
  if [[ -n "$body" ]]; then
    printf '\n## %s\n\n```text\n%s\n```\n' "$title" "$body" >> "$file"
  fi
}

build_run_log_excerpt() {
  local status="$1"
  local last_failure_reason="$2"
  local run_log="$3"
  local excerpt=""
  local pattern='error|failed|exception|traceback|command not found|not found|timeout|timed out|refused|denied|no such file|cannot|invalid|panic'

  if [[ -z "$run_log" || ! -f "$run_log" ]]; then
    return 0
  fi

  if [[ -n "$last_failure_reason" || "$status" =~ failed|needs_update|retrying|ci_failed|archived ]]; then
    excerpt="$(rg -i -n "$pattern" "$run_log" | tail -n 20 || true)"
    if [[ -z "$excerpt" ]]; then
      excerpt="$(tail -n 40 "$run_log" || true)"
    fi
  fi

  printf '%s' "$excerpt"
}

sync_summary() {
  local summary_file="$1"
  local target_dir="$BRAIN_DIR/projects/openclaw-tasks"
  local tmp target_file changed
  local task_id title project_id status type priority branch repo_path worktree_path
  local pr_url created_at started_at finished_at updated_at archived_at archived_from
  local generated_at stage verification_evidence last_failure_reason last_failure_class
  local run_log run_log_first_line command run_excerpt title_suffix source_note
  local page_title created_value project_tag status_tag

  if [[ ! -f "$summary_file" ]]; then
    echo "summary file not found: $summary_file" >&2
    return 1
  fi

  task_id="$(jq -r '.id // empty' "$summary_file")"
  if [[ -z "$task_id" ]]; then
    echo "summary file missing task id: $summary_file" >&2
    return 1
  fi

  title="$(jq -r '.title // ""' "$summary_file")"
  project_id="$(jq -r '.projectId // ""' "$summary_file")"
  status="$(jq -r '.status // ""' "$summary_file")"
  type="$(jq -r '.type // ""' "$summary_file")"
  priority="$(jq -r '.priority // ""' "$summary_file")"
  branch="$(jq -r '.branch // ""' "$summary_file")"
  repo_path="$(jq -r '.repoPath // ""' "$summary_file")"
  worktree_path="$(jq -r '.worktreePath // ""' "$summary_file")"
  pr_url="$(jq -r '.prUrl // ""' "$summary_file")"
  created_at="$(jq -r '.createdAt // ""' "$summary_file")"
  started_at="$(jq -r '.startedAt // ""' "$summary_file")"
  finished_at="$(jq -r '.finishedAt // ""' "$summary_file")"
  updated_at="$(jq -r '.updatedAt // ""' "$summary_file")"
  archived_at="$(jq -r '.archivedAt // ""' "$summary_file")"
  archived_from="$(jq -r '.archivedFrom // ""' "$summary_file")"
  generated_at="$(jq -r '.summaryMeta.generatedAt // ""' "$summary_file")"
  stage="$(jq -r '.summaryMeta.stage // ""' "$summary_file")"
  verification_evidence="$(jq -r '.verification.evidence // ""' "$summary_file")"
  last_failure_reason="$(jq -r '.lastFailure.reason // ""' "$summary_file")"
  last_failure_class="$(jq -r '.lastFailure.classification // ""' "$summary_file")"

  run_log="$(extract_from_evidence "runLog" "$verification_evidence")"
  run_log_first_line="$(extract_from_evidence "runLogFirstLine" "$verification_evidence")"
  command="$(extract_from_evidence "command" "$verification_evidence")"
  run_excerpt="$(build_run_log_excerpt "$status" "$last_failure_reason" "$run_log")"

  mkdir -p "$target_dir"
  target_file="$target_dir/$task_id.md"
  tmp="$(mktemp)"

  title_suffix=""
  if [[ -n "$title" ]]; then
    title_suffix=" - $title"
  fi

  page_title="Task $task_id"
  if [[ -n "$title" ]]; then
    page_title="$page_title - $title"
  fi

  created_value="$created_at"
  if [[ -z "$created_value" ]]; then
    created_value="$generated_at"
  fi

  project_tag="$(slugify "$project_id")"
  status_tag="$(slugify "$status")"

  source_note="OpenClaw task summary ($(basename "$summary_file"))"
  if [[ -n "$generated_at" ]]; then
    source_note="$source_note generated at $generated_at"
  fi

  printf -- '---\n' > "$tmp"
  printf 'type: project\n' >> "$tmp"
  printf 'title: "%s"\n' "$(printf '%s' "$page_title" | sed 's/"/\\"/g')" >> "$tmp"
  if [[ -n "$created_value" ]]; then
    printf 'created: "%s"\n' "$created_value" >> "$tmp"
  fi
  printf 'tags:\n' >> "$tmp"
  printf -- '  - openclaw-task\n' >> "$tmp"
  if [[ -n "$project_tag" ]]; then
    printf '  - project-%s\n' "$project_tag" >> "$tmp"
  fi
  if [[ -n "$status_tag" ]]; then
    printf '  - status-%s\n' "$status_tag" >> "$tmp"
  fi
  printf -- '---\n\n' >> "$tmp"
  printf '# Task %s%s\n\n' "$task_id" "$title_suffix" >> "$tmp"
  printf '## Compiled Truth\n\n' >> "$tmp"
  printf -- '- taskId: `%s`\n' "$task_id" >> "$tmp"
  append_bullet_if_present "$tmp" "title" "$title"
  append_bullet_if_present "$tmp" "project" "$project_id"
  append_bullet_if_present "$tmp" "status" "$status"
  append_bullet_if_present "$tmp" "type" "$type"
  append_bullet_if_present "$tmp" "priority" "$priority"
  append_bullet_if_present "$tmp" "branch" "$branch"
  append_bullet_if_present "$tmp" "prUrl" "$pr_url"
  append_bullet_if_present "$tmp" "repoPath" "$repo_path"
  append_bullet_if_present "$tmp" "worktreePath" "$worktree_path"
  append_bullet_if_present "$tmp" "summaryStage" "$stage"
  append_bullet_if_present "$tmp" "lastFailureReason" "$last_failure_reason"
  append_bullet_if_present "$tmp" "lastFailureClass" "$last_failure_class"
  append_bullet_if_present "$tmp" "runLog" "$run_log"
  append_bullet_if_present "$tmp" "runLogFirstLine" "$run_log_first_line"
  append_bullet_if_present "$tmp" "source" "$source_note"

  printf '\n## Timeline\n\n' >> "$tmp"
  append_bullet_if_present "$tmp" "createdAt" "$created_at"
  append_bullet_if_present "$tmp" "startedAt" "$started_at"
  append_bullet_if_present "$tmp" "finishedAt" "$finished_at"
  append_bullet_if_present "$tmp" "updatedAt" "$updated_at"
  append_bullet_if_present "$tmp" "archivedAt" "$archived_at"
  append_bullet_if_present "$tmp" "archivedFrom" "$archived_from"

  if [[ -n "$command" ]]; then
    printf '\n## Execution Command\n\n```text\n%s\n```\n' "$command" >> "$tmp"
  fi

  write_section_block "$tmp" "Verification Evidence" "$verification_evidence"
  write_section_block "$tmp" "Run Log Signal" "$run_excerpt"

  changed=1
  if [[ -f "$target_file" ]] && cmp -s "$tmp" "$target_file" && [[ "$FORCE" -eq 0 ]]; then
    changed=0
    rm -f "$tmp"
  else
    mv "$tmp" "$target_file"
  fi

  if [[ "$IMPORT" -eq 1 && "$changed" -eq 1 ]]; then
    if command -v gbrain >/dev/null 2>&1; then
      gbrain import "$target_dir" --no-embed >/dev/null
    else
      echo "gbrain not found in PATH, skipped import for $task_id" >&2
    fi
  fi

  if [[ "$changed" -eq 1 ]]; then
    echo "synced task summary to brain: $target_file"
  else
    echo "task summary unchanged: $target_file"
  fi
}

require_bin jq
require_bin rg

if [[ -n "$SUMMARY_FILE" && "$SYNC_ALL" -eq 1 ]]; then
  echo "use either --summary-file or --all" >&2
  exit 1
fi

if [[ -n "$SUMMARY_FILE" ]]; then
  sync_summary "$SUMMARY_FILE"
  exit 0
fi

if [[ "$SYNC_ALL" -eq 1 ]]; then
  found=0
  while IFS= read -r file; do
    found=1
    sync_summary "$file"
  done < <(find "$ROOT/summaries" -maxdepth 1 -type f -name '*.json' | sort)
  if [[ "$found" -eq 0 ]]; then
    echo "no summary files found under $ROOT/summaries"
  fi
  exit 0
fi

usage
exit 1
