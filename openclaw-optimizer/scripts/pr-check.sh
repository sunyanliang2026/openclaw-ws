#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/home/ubuntu/.openclaw/workspace/openclaw-optimizer/runtime}"
ACTIVE_DIR="$ROOT/tasks/active"
COMPLETED_DIR="$ROOT/tasks/completed"
FAILED_DIR="$ROOT/tasks/failed"
LOG_DIR="$ROOT/logs"
EVENT_DIR="$ROOT/events"
LOG_FILE="$LOG_DIR/pr-check-$(date +%Y%m%d).log"
EVENT_FILE="$EVENT_DIR/pr-check-events-$(date +%Y%m%d).jsonl"
QUALITY_CONFIG="${QUALITY_CONFIG:-/home/ubuntu/.openclaw/workspace/openclaw-optimizer/config/quality-gates.json}"
NOTIFY_TASK_COMPLETION_SCRIPT="/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/notify-task-completion.sh"
SUMMARY_SCRIPT="/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/write-task-summary.sh"

mkdir -p "$ACTIVE_DIR" "$COMPLETED_DIR" "$FAILED_DIR" "$LOG_DIR" "$EVENT_DIR"

log() {
  echo "[$(date -Is)] $*" | tee -a "$LOG_FILE"
}

log_event() {
  local event="$1"
  local task_id="${2:-}"
  local status="${3:-}"
  local detail="${4:-}"
  jq -cn \
    --arg ts "$(date -Is)" \
    --arg event "$event" \
    --arg taskId "$task_id" \
    --arg status "$status" \
    --arg detail "$detail" \
    '{ts:$ts,event:$event,taskId:$taskId,status:$status,detail:$detail}' >> "$EVENT_FILE"
}

require_bin() {
  command -v "$1" >/dev/null 2>&1 || {
    log "missing binary: $1"
    exit 1
  }
}

require_bin jq
require_bin gh
require_bin git

quality_required_sections=()
quality_required_task_fields=()
quality_require_tests_passed=true
quality_auto_comment_on_needs_update=true
quality_comment_tag="openclaw-quality-gate"
quality_require_mergeable=true
quality_max_behind_commits=20

if [[ -f "$QUALITY_CONFIG" ]]; then
  mapfile -t quality_required_sections < <(jq -r '.requiredPrSections[]? // empty' "$QUALITY_CONFIG")
  mapfile -t quality_required_task_fields < <(jq -r '.requiredTaskFields[]? // empty' "$QUALITY_CONFIG")
  quality_require_tests_passed="$(jq -r '.requireTestsPassed // true' "$QUALITY_CONFIG")"
  quality_auto_comment_on_needs_update="$(jq -r '.autoCommentOnNeedsUpdate // true' "$QUALITY_CONFIG")"
  quality_comment_tag="$(jq -r '.commentTag // "openclaw-quality-gate"' "$QUALITY_CONFIG")"
  quality_require_mergeable="$(jq -r '.requireMergeable // true' "$QUALITY_CONFIG")"
  quality_max_behind_commits="$(jq -r '.maxBehindCommits // 20' "$QUALITY_CONFIG")"
else
  quality_required_sections=("Validation" "Risk" "Rollback")
  quality_required_task_fields=("verification.testCommand" "verification.testsPassed")
  quality_require_tests_passed=true
  quality_auto_comment_on_needs_update=true
  quality_comment_tag="openclaw-quality-gate"
  quality_require_mergeable=true
  quality_max_behind_commits=20
fi

has_non_empty_field() {
  local file="$1"
  local path="$2"
  jq -e --arg p "$path" '
    getpath($p | split(".")) as $v
    | ($v != null) and (($v|type) != "string" or ($v|length) > 0)
  ' "$file" >/dev/null 2>&1
}

task_tests_passed() {
  local file="$1"
  jq -e '.verification.testsPassed == true' "$file" >/dev/null 2>&1
}

infer_test_command_from_body() {
  local body="$1"
  awk '
    match($0, /`[^`]*test:[^`]*`/) {
      cmd=substr($0, RSTART+1, RLENGTH-2);
      print cmd;
      exit;
    }
  ' <<< "$body"
}

infer_tests_passed_from_body() {
  local body="$1"
  if grep -Eiq 'pass(ing|ed)' <<< "$body"; then
    echo true
  else
    echo false
  fi
}

hash_text() {
  local text="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$text" | sha256sum | awk '{print $1}'
  else
    printf '%s' "$text" | shasum -a 256 | awk '{print $1}'
  fi
}

pr_api_path_from_url() {
  local url="$1"
  if [[ "$url" =~ github\.com/([^/]+)/([^/]+)/pull/([0-9]+) ]]; then
    local owner="${BASH_REMATCH[1]}"
    local repo="${BASH_REMATCH[2]}"
    local number="${BASH_REMATCH[3]}"
    echo "repos/${owner}/${repo}/pulls/${number}"
    return 0
  fi
  return 1
}

fetch_pr_body() {
  local url="$1"
  local api_path
  api_path="$(pr_api_path_from_url "$url" || true)"
  if [[ -z "$api_path" ]]; then
    echo ""
    return 0
  fi
  gh api "$api_path" --jq '.body' 2>/dev/null || echo ""
}

fetch_pr_field() {
  local url="$1"
  local jq_expr="$2"
  local api_path
  api_path="$(pr_api_path_from_url "$url" || true)"
  if [[ -z "$api_path" ]]; then
    echo ""
    return 0
  fi
  gh api "$api_path" --jq "$jq_expr" 2>/dev/null || echo ""
}

notify_task_file() {
  local file="$1"
  local event="${2:-status_changed}"
  if [[ -x "$NOTIFY_TASK_COMPLETION_SCRIPT" && -f "$file" ]]; then
    "$NOTIFY_TASK_COMPLETION_SCRIPT" --task-file "$file" --event "$event" "$ROOT" >> "$LOG_FILE" 2>&1 || true
  fi
}

resolve_behind_count() {
  local repo_path="$1"
  local base_branch="$2"
  local head_branch="$3"
  if [[ -z "$base_branch" || -z "$head_branch" ]]; then
    echo ""
    return 0
  fi
  git -C "$repo_path" fetch origin "$base_branch" "$head_branch" >/dev/null 2>&1 || true
  git -C "$repo_path" rev-list --left-right --count "origin/$base_branch...$head_branch" 2>/dev/null | awk '{print $1}' || echo ""
}

shopt -s nullglob
for task_file in "$ACTIVE_DIR"/*.json; do
  task_id="$(basename "$task_file" .json)"
  status="$(jq -r '.status // "pending"' "$task_file")"
  repo_path="$(jq -r '.repoPath // empty' "$task_file")"
  branch="$(jq -r '.branch // empty' "$task_file")"

  if [[ -z "$repo_path" || -z "$branch" ]]; then
    log "skip task=$task_id missing repoPath/branch"
    continue
  fi

  if [[ ! -e "$repo_path/.git" ]]; then
    log "skip task=$task_id invalid repoPath=$repo_path"
    continue
  fi

  pr_json="$(cd "$repo_path" && gh pr list --head "$branch" --json url,state,statusCheckRollup --limit 1 2>/dev/null || echo '[]')"

  if [[ "$(jq 'length' <<< "$pr_json")" -eq 0 ]]; then
    log "task=$task_id no PR yet for branch=$branch"
    log_event "pr_missing" "$task_id" "$status" "branch=$branch"
    continue
  fi

  pr_url="$(jq -r '.[0].url // empty' <<< "$pr_json")"
  pr_state="$(jq -r '.[0].state // "UNKNOWN"' <<< "$pr_json")"
  pending_checks="$(jq '[.[0].statusCheckRollup[]? | select((.status // "") == "IN_PROGRESS" or (.status // "") == "QUEUED")] | length' <<< "$pr_json")"
  failed_checks="$(jq '[.[0].statusCheckRollup[]? | select((.conclusion // "") == "FAILURE" or (.conclusion // "") == "CANCELLED" or (.conclusion // "") == "TIMED_OUT" or (.conclusion // "") == "ACTION_REQUIRED")] | length' <<< "$pr_json")"

  tmp="$(mktemp)"
  jq --arg pr "$pr_url" --arg now "$(date -Is)" '.prUrl = $pr | .updatedAt = $now' "$task_file" > "$tmp"
  mv "$tmp" "$task_file"

  log "task=$task_id state=$pr_state failed_checks=$failed_checks pending_checks=$pending_checks pr=$pr_url"
  log_event "pr_checked" "$task_id" "$status" "pr_state=$pr_state failed_checks=$failed_checks pending_checks=$pending_checks"

  if [[ "$pr_state" == "MERGED" ]]; then
    tmp="$(mktemp)"
    jq --arg now "$(date -Is)" '.status = "completed" | .completedAt = $now | .updatedAt = $now' "$task_file" > "$tmp"
    mv "$tmp" "$COMPLETED_DIR/$task_id.json"
    rm -f "$task_file"
    if [[ -x "$SUMMARY_SCRIPT" ]]; then
      "$SUMMARY_SCRIPT" --task-file "$COMPLETED_DIR/$task_id.json" --stage updated "$ROOT" >/dev/null 2>&1 || true
    fi
    log "task=$task_id moved to completed"
    log_event "task_completed" "$task_id" "completed" "reason=pr_merged"
    notify_task_file "$COMPLETED_DIR/$task_id.json" "pr_merged_completed"
    continue
  fi

  if [[ "$pr_state" == "CLOSED" ]]; then
    tmp="$(mktemp)"
    jq --arg now "$(date -Is)" '.status = "failed" | .lastFailure.reason = "pr_closed_not_merged" | .lastFailure.classification = "code" | .updatedAt = $now' "$task_file" > "$tmp"
    mv "$tmp" "$FAILED_DIR/$task_id.json"
    rm -f "$task_file"
    notify_task_file "$FAILED_DIR/$task_id.json" "pr_closed_not_merged"
    log "task=$task_id moved to failed (closed PR)"
    log_event "task_failed" "$task_id" "failed" "reason=pr_closed_not_merged"
    continue
  fi

  if [[ "$failed_checks" -gt 0 ]]; then
    tmp="$(mktemp)"
    jq --arg now "$(date -Is)" '.status = "ci_failed" | .lastFailure.reason = "ci_checks_failed" | .lastFailure.classification = "ci" | .updatedAt = $now' "$task_file" > "$tmp"
    mv "$tmp" "$task_file"
    notify_task_file "$task_file" "ci_checks_failed"
    log_event "status_changed" "$task_id" "ci_failed" "failed_checks=$failed_checks"
    continue
  fi

  quality_issues=()
  pr_body="$(fetch_pr_body "$pr_url")"
  pr_mergeable="$(fetch_pr_field "$pr_url" '.mergeable')"
  pr_mergeable_state="$(fetch_pr_field "$pr_url" '.mergeable_state // ""')"
  pr_base_branch="$(fetch_pr_field "$pr_url" '.base.ref // ""')"
  behind_count="$(resolve_behind_count "$repo_path" "$pr_base_branch" "$branch")"

  # Backfill verification from PR body when missing.
  if ! has_non_empty_field "$task_file" "verification.testCommand"; then
    inferred_cmd="$(infer_test_command_from_body "$pr_body")"
    if [[ -n "$inferred_cmd" ]]; then
      tmp="$(mktemp)"
      jq --arg cmd "$inferred_cmd" '.verification.testCommand = $cmd' "$task_file" > "$tmp"
      mv "$tmp" "$task_file"
    fi
  fi

  if ! has_non_empty_field "$task_file" "verification.testsPassed"; then
    inferred_passed="$(infer_tests_passed_from_body "$pr_body")"
    tmp="$(mktemp)"
    jq --argjson passed "$inferred_passed" '.verification.testsPassed = $passed' "$task_file" > "$tmp"
    mv "$tmp" "$task_file"
  fi

  for section in "${quality_required_sections[@]}"; do
    if ! grep -Eiq "^##[[:space:]]+$section([[:space:]]|$)" <<< "$pr_body"; then
      quality_issues+=("missing_pr_section:$section")
    fi
  done

  for field_path in "${quality_required_task_fields[@]}"; do
    if ! has_non_empty_field "$task_file" "$field_path"; then
      quality_issues+=("missing_task_field:$field_path")
    fi
  done

  if [[ "$quality_require_tests_passed" == "true" ]]; then
    if ! task_tests_passed "$task_file"; then
      quality_issues+=("tests_not_marked_passed")
    fi
  fi

  if [[ "$quality_require_mergeable" == "true" ]]; then
    if [[ "$pr_mergeable" != "true" ]]; then
      quality_issues+=("pr_not_mergeable")
    fi
    if [[ "$pr_mergeable_state" == "dirty" || "$pr_mergeable_state" == "blocked" ]]; then
      quality_issues+=("pr_mergeable_state:$pr_mergeable_state")
    fi
    if [[ -n "$behind_count" ]] && [[ "$behind_count" != "null" ]]; then
      if [[ "$behind_count" =~ ^[0-9]+$ ]] && (( behind_count > quality_max_behind_commits )); then
        quality_issues+=("branch_behind_base:$behind_count")
      fi
    fi
  fi

  if (( ${#quality_issues[@]} > 0 )); then
    issues_json="$(printf '%s\n' "${quality_issues[@]}" | jq -R . | jq -s .)"
    issues_text="$(printf '%s\n' "${quality_issues[@]}")"
    issue_fingerprint="$(hash_text "$issues_text")"
    last_fingerprint="$(jq -r '.qualityGate.lastCommentFingerprint // empty' "$task_file")"

    if [[ "$quality_auto_comment_on_needs_update" == "true" ]] && [[ "$issue_fingerprint" != "$last_fingerprint" ]]; then
      comment_body="<!-- ${quality_comment_tag} -->
Quality gate failed for task \`${task_id}\`.

Required updates:
$(printf '%s\n' "${quality_issues[@]}" | sed 's/^/- /')

Please update PR description/verification metadata and rerun checks."
      if cd "$repo_path" && gh pr comment "$pr_url" --body "$comment_body" >/dev/null 2>&1; then
        log "task=$task_id posted quality-gate comment on PR"
        log_event "quality_comment_posted" "$task_id" "needs_update" "pr=$pr_url"
      else
        log "task=$task_id failed to post quality-gate comment"
        log_event "quality_comment_failed" "$task_id" "needs_update" "pr=$pr_url"
      fi
    fi

    tmp="$(mktemp)"
    jq \
      --arg now "$(date -Is)" \
      --arg fp "$issue_fingerprint" \
      --argjson issues "$issues_json" \
      '.status = "needs_update"
      | .updatedAt = $now
      | .qualityGate.passed = false
      | .qualityGate.checkedAt = $now
      | .qualityGate.issues = $issues
      | .qualityGate.lastCommentFingerprint = $fp' \
      "$task_file" > "$tmp"
    mv "$tmp" "$task_file"
    notify_task_file "$task_file" "needs_update"
    log "task=$task_id marked needs_update issues=$(IFS=,; echo "${quality_issues[*]}")"
    log_event "status_changed" "$task_id" "needs_update" "issues=$(IFS=,; echo "${quality_issues[*]}")"
    continue
  fi

  if [[ "$pending_checks" -eq 0 ]]; then
    tmp="$(mktemp)"
    jq --arg now "$(date -Is)" '.status = "ready_for_review" | .updatedAt = $now | .qualityGate.passed = true | .qualityGate.checkedAt = $now | .qualityGate.issues = []' "$task_file" > "$tmp"
    mv "$tmp" "$task_file"
    notify_task_file "$task_file" "quality_gate_ready_for_review"
    log_event "status_changed" "$task_id" "ready_for_review" "pending_checks=0"
  else
    tmp="$(mktemp)"
    jq --arg now "$(date -Is)" '.status = "ci_running" | .updatedAt = $now | .qualityGate.passed = true | .qualityGate.checkedAt = $now | .qualityGate.issues = []' "$task_file" > "$tmp"
    mv "$tmp" "$task_file"
    notify_task_file "$task_file" "quality_gate_ci_running"
    log_event "status_changed" "$task_id" "ci_running" "pending_checks=$pending_checks"
  fi
done

log "pr-check completed"
