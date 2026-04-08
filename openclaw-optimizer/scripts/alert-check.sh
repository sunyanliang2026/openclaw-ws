#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/home/ubuntu/.openclaw/workspace/openclaw-optimizer/runtime}"
ALERT_CONFIG="${ALERT_CONFIG:-/home/ubuntu/.openclaw/workspace/openclaw-optimizer/config/alerts.json}"
LOG_DIR="$ROOT/logs"
EVENT_DIR="$ROOT/events"
STATE_DIR="$ROOT/state"
LOG_FILE="$LOG_DIR/alert-check-$(date +%Y%m%d).log"
EVENT_FILE="$EVENT_DIR/alert-events-$(date +%Y%m%d).jsonl"
STATE_FILE="$STATE_DIR/alert-state.json"
METRICS_SCRIPT="/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/metrics-report.sh"

mkdir -p "$LOG_DIR" "$EVENT_DIR" "$STATE_DIR"

# Backward-compatible state migration from legacy log location.
if [[ ! -f "$STATE_FILE" && -f "$LOG_DIR/alert-state.json" ]]; then
  cp "$LOG_DIR/alert-state.json" "$STATE_FILE"
fi

require_bin() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing binary: $1"
    exit 1
  }
}

require_bin jq
require_bin curl

log() {
  echo "[$(date -Is)] $*" | tee -a "$LOG_FILE"
}

log_event() {
  local event="$1"
  local severity="$2"
  local detail="$3"
  jq -cn \
    --arg ts "$(date -Is)" \
    --arg event "$event" \
    --arg severity "$severity" \
    --arg detail "$detail" \
    '{ts:$ts,event:$event,severity:$severity,detail:$detail}' >> "$EVENT_FILE"
}

window_hours=24
threshold_run_timeouts=1
threshold_queue_timeouts=1
threshold_ci_failed=3
threshold_retry=5
notify_enabled=false
notify_cooldown_minutes=180
notify_feishu_webhook=""
notify_slack_webhook=""
notify_generic_webhook=""
notify_generic_bearer=""
notify_timeout_seconds=10

if [[ -f "$ALERT_CONFIG" ]]; then
  window_hours="$(jq -r '.windowHours // 24' "$ALERT_CONFIG")"
  threshold_run_timeouts="$(jq -r '.thresholds.runTimeouts // 1' "$ALERT_CONFIG")"
  threshold_queue_timeouts="$(jq -r '.thresholds.queueTimeouts // 1' "$ALERT_CONFIG")"
  threshold_ci_failed="$(jq -r '.thresholds.ciFailedTransitions // 3' "$ALERT_CONFIG")"
  threshold_retry="$(jq -r '.thresholds.retryTransitions // 5' "$ALERT_CONFIG")"
  notify_enabled="$(jq -r '.notifications.enabled // false' "$ALERT_CONFIG")"
  notify_cooldown_minutes="$(jq -r '.notifications.cooldownMinutes // 180' "$ALERT_CONFIG")"
  notify_feishu_webhook="$(jq -r '.notifications.feishuWebhook // ""' "$ALERT_CONFIG")"
  notify_slack_webhook="$(jq -r '.notifications.slackWebhook // ""' "$ALERT_CONFIG")"
  notify_generic_webhook="$(jq -r '.notifications.genericWebhook // ""' "$ALERT_CONFIG")"
  notify_timeout_seconds="$(jq -r '.notifications.timeoutSeconds // 10' "$ALERT_CONFIG")"
fi

notify_feishu_webhook="${ALERT_FEISHU_WEBHOOK:-$notify_feishu_webhook}"
notify_slack_webhook="${ALERT_SLACK_WEBHOOK:-$notify_slack_webhook}"
notify_generic_webhook="${ALERT_GENERIC_WEBHOOK:-$notify_generic_webhook}"
notify_generic_bearer="${ALERT_GENERIC_BEARER:-$notify_generic_bearer}"

metrics_json="$("$METRICS_SCRIPT" "$ROOT" --hours "$window_hours" --json)"

run_timeouts="$(jq -r '.runTimeouts // 0' <<< "$metrics_json")"
queue_timeouts="$(jq -r '.queueTimeouts // 0' <<< "$metrics_json")"
ci_failed="$(jq -r '.ciFailedTransitions // 0' <<< "$metrics_json")"
retries="$(jq -r '.retryTransitions // 0' <<< "$metrics_json")"

alerts=()

if (( run_timeouts >= threshold_run_timeouts )); then
  alerts+=("run_timeouts=$run_timeouts threshold=$threshold_run_timeouts")
fi
if (( queue_timeouts >= threshold_queue_timeouts )); then
  alerts+=("queue_timeouts=$queue_timeouts threshold=$threshold_queue_timeouts")
fi
if (( ci_failed >= threshold_ci_failed )); then
  alerts+=("ci_failed_transitions=$ci_failed threshold=$threshold_ci_failed")
fi
if (( retries >= threshold_retry )); then
  alerts+=("retry_transitions=$retries threshold=$threshold_retry")
fi

if (( ${#alerts[@]} == 0 )); then
  log "alert-check ok window=${window_hours}h"
  log_event "alert_check_ok" "info" "window=${window_hours}h"
  exit 0
fi

detail="$(printf '%s; ' "${alerts[@]}")"
log "alert-check triggered: $detail"
log_event "alert_check_triggered" "warn" "$detail"

alert_fingerprint="$(printf '%s' "$detail" | sha256sum | awk '{print $1}')"
now_epoch="$(date +%s)"
last_fp=""
last_sent_epoch=0
if [[ -f "$STATE_FILE" ]]; then
  last_fp="$(jq -r '.lastTriggeredFingerprint // ""' "$STATE_FILE" 2>/dev/null || true)"
  last_sent_epoch="$(jq -r '.lastSentEpoch // 0' "$STATE_FILE" 2>/dev/null || true)"
fi
if [[ -z "$last_sent_epoch" || "$last_sent_epoch" == "null" ]]; then
  last_sent_epoch=0
fi
next_allowed_epoch=$((last_sent_epoch + notify_cooldown_minutes * 60))

should_notify=false
if [[ "${ALERT_FORCE_TRIGGER:-0}" == "1" ]]; then
  should_notify=true
elif [[ "$alert_fingerprint" != "$last_fp" ]]; then
  should_notify=true
elif (( now_epoch >= next_allowed_epoch )); then
  should_notify=true
fi

send_feishu() {
  local webhook="$1"
  local msg="$2"
  [[ -z "$webhook" ]] && return 0
  local payload
  payload="$(jq -cn --arg text "$msg" '{msg_type:"text",content:{text:$text}}')"
  curl -sS --max-time "$notify_timeout_seconds" -H 'Content-Type: application/json' -d "$payload" "$webhook" >/dev/null
}

send_slack() {
  local webhook="$1"
  local msg="$2"
  [[ -z "$webhook" ]] && return 0
  local payload
  payload="$(jq -cn --arg text "$msg" '{text:$text}')"
  curl -sS --max-time "$notify_timeout_seconds" -H 'Content-Type: application/json' -d "$payload" "$webhook" >/dev/null
}

send_generic() {
  local webhook="$1"
  local msg="$2"
  local detail="$3"
  [[ -z "$webhook" ]] && return 0
  local payload
  payload="$(jq -cn --arg msg "$msg" --arg detail "$detail" '{message:$msg,detail:$detail,severity:"warn"}')"
  if [[ -n "$notify_generic_bearer" ]]; then
    curl -sS --max-time "$notify_timeout_seconds" -H 'Content-Type: application/json' -H "Authorization: Bearer $notify_generic_bearer" -d "$payload" "$webhook" >/dev/null
  else
    curl -sS --max-time "$notify_timeout_seconds" -H 'Content-Type: application/json' -d "$payload" "$webhook" >/dev/null
  fi
}

if [[ "$notify_enabled" == "true" && "$should_notify" == "true" ]]; then
  notify_msg="[openclaw-optimizer] alert triggered (${window_hours}h window)"
  notify_ok=true
  if ! send_feishu "$notify_feishu_webhook" "$notify_msg: $detail"; then
    notify_ok=false
    log_event "alert_notify_failed" "warn" "channel=feishu"
  fi
  if ! send_slack "$notify_slack_webhook" "$notify_msg: $detail"; then
    notify_ok=false
    log_event "alert_notify_failed" "warn" "channel=slack"
  fi
  if ! send_generic "$notify_generic_webhook" "$notify_msg" "$detail"; then
    notify_ok=false
    log_event "alert_notify_failed" "warn" "channel=generic"
  fi

  tmp="$(mktemp)"
  jq -cn \
    --arg fp "$alert_fingerprint" \
    --argjson sent "$now_epoch" \
    --arg ts "$(date -Is)" \
    '{lastTriggeredFingerprint:$fp,lastSentEpoch:$sent,lastSentAt:$ts}' > "$tmp"
  mv "$tmp" "$STATE_FILE"

  if [[ "$notify_ok" == "true" ]]; then
    log_event "alert_notified" "warn" "fingerprint=$alert_fingerprint"
  fi
elif [[ "$notify_enabled" == "true" ]]; then
  log_event "alert_notify_suppressed" "info" "fingerprint=$alert_fingerprint cooldownMinutes=$notify_cooldown_minutes"
fi

exit 2
