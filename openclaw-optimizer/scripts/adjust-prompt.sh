#!/usr/bin/env bash
set -euo pipefail

TASK_FILE="${1:-}"
FAIL_REASON="${2:-unknown}"
ATTEMPT="${3:-1}"
FAIL_CLASS="${4:-unknown}"

if [[ -z "$TASK_FILE" || ! -f "$TASK_FILE" ]]; then
  echo "Usage: $0 <task_file> [fail_reason] [attempt]"
  exit 1
fi

require_bin() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing binary: $1"
    exit 1
  }
}

require_bin jq

base_prompt="$(jq -r '.launch.basePrompt // .launch.initialPrompt // empty' "$TASK_FILE")"
constraints="$(jq -r '.context.constraints[]? // empty' "$TASK_FILE" | sed 's/^/- /')"
success_criteria="$(jq -r '.context.successCriteria[]? // empty' "$TASK_FILE" | sed 's/^/- /')"

if [[ -z "$base_prompt" ]]; then
  base_prompt="Describe the exact implementation task in one paragraph and then execute it."
fi

retry_guidance=""
case "$FAIL_CLASS" in
  infra)
    retry_guidance="Execution ended unexpectedly. Use smaller checkpoints, log progress every 2-3 steps, and verify after each checkpoint."
    ;;
  code)
    retry_guidance="Likely implementation defect. Reproduce locally first, apply minimal diff, and include targeted regression checks."
    ;;
  ci)
    retry_guidance="CI-related failure. Reproduce CI checks locally, fix failing checks first, then rerun full required test commands."
    ;;
  auth)
    retry_guidance="Authentication/credential issue. Verify auth profile/token validity before coding changes."
    ;;
  rate_limit)
    retry_guidance="Rate limit reached. Wait for reset window, then resume with minimal calls and deterministic checks first."
    ;;
  *)
    retry_guidance="Previous run did not complete. Re-validate assumptions first, then execute incrementally with verification evidence."
    ;;
esac

new_prompt="$base_prompt

Retry context:
- attempt: $ATTEMPT
- failure: $FAIL_REASON
- class: $FAIL_CLASS
- guidance: $retry_guidance"

if [[ -n "$constraints" ]]; then
  new_prompt="$new_prompt

Constraints:
$constraints"
fi

if [[ -n "$success_criteria" ]]; then
  new_prompt="$new_prompt

Success criteria:
$success_criteria"
fi

new_prompt="$new_prompt

Output requirement:
- End with exact commands run and pass/fail results."

tmp="$(mktemp)"
jq \
  --arg base "$base_prompt" \
  --arg prompt "$new_prompt" \
  --arg reason "$FAIL_REASON" \
  --arg klass "$FAIL_CLASS" \
  --arg now "$(date -Is)" \
  '.launch.basePrompt = $base
  | .launch.initialPrompt = $prompt
  | .lastFailure.promptAdjustment = ("adjusted_for_" + $reason)
  | .lastFailure.classification = $klass
  | .updatedAt = $now' \
  "$TASK_FILE" > "$tmp"
mv "$tmp" "$TASK_FILE"

echo "adjusted prompt for $(basename "$TASK_FILE" .json) reason=$FAIL_REASON attempt=$ATTEMPT"
