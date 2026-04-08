#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/ubuntu/.openclaw/workspace/openclaw-optimizer/runtime"
WINDOW_HOURS="${WINDOW_HOURS:-24}"
OUTPUT_JSON=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json)
      OUTPUT_JSON=1
      shift
      ;;
    --hours)
      WINDOW_HOURS="${2:-24}"
      shift 2
      ;;
    *)
      if [[ "$1" =~ ^[0-9]+$ ]]; then
        WINDOW_HOURS="$1"
      else
        ROOT="$1"
      fi
      shift
      ;;
  esac
done

LOG_DIR="$ROOT/logs"
EVENT_DIR="$ROOT/events"
CUTOFF_EPOCH=$(( $(date +%s) - WINDOW_HOURS * 3600 ))

require_bin() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing binary: $1"
    exit 1
  }
}

require_bin jq
require_bin date

events_tmp="$(mktemp)"
window_events_tmp="$(mktemp)"
trap 'rm -f "$events_tmp" "$window_events_tmp"' EXIT

shopt -s nullglob
for f in "$EVENT_DIR"/*events-*.jsonl; do
  cat "$f" >> "$events_tmp"
done
for f in "$LOG_DIR"/*events-*.jsonl; do
  cat "$f" >> "$events_tmp"
done

if [[ ! -s "$events_tmp" ]]; then
  printf '{"windowHours":%s,"note":"no_event_logs"}\n' "$WINDOW_HOURS"
  exit 0
fi

while IFS= read -r line; do
  ts="$(jq -r '.ts // empty' <<< "$line" 2>/dev/null || true)"
  [[ -z "$ts" ]] && continue
  ev_epoch="$(date -d "$ts" +%s 2>/dev/null || true)"
  [[ -z "$ev_epoch" ]] && continue
  if (( ev_epoch >= CUTOFF_EPOCH )); then
    printf '%s\n' "$line" >> "$window_events_tmp"
  fi
done < "$events_tmp"

if [[ ! -s "$window_events_tmp" ]]; then
  if [[ "$OUTPUT_JSON" -eq 1 ]]; then
    jq -cn --argjson h "$WINDOW_HOURS" '{windowHours:$h,generatedAt:(now|todateiso8601),retryTransitions:0,ciFailedTransitions:0,readyForReviewTransitions:0,queueTransitions:0,runTimeouts:0,queueTimeouts:0,totalEvents:0,avgQueueSeconds:0,avgQueueSamples:0,completedInWindow:0,statusCounts:[]}'
  else
    echo "OpenClaw Optimizer Metrics"
    echo "window_hours=$WINDOW_HOURS generated_at=$(date -Is)"
    echo "total_events=0"
  fi
  exit 0
fi

metrics_json="$(jq -cn \
  --slurpfile events "$window_events_tmp" \
  --argjson hours "$WINDOW_HOURS" '
  def event_list: ($events // []);
  def count_by_event($name): (event_list | map(select(.event == $name)) | length);
  def count_by_status_change($status): (event_list | map(select(.event == "status_changed" and .status == $status)) | length);
  def count_timeout($kind): (event_list | map(select(.event == "task_failed_timeout" and ((.detail // "") | contains("failure=" + $kind)))) | length);
  {
    windowHours: $hours,
    generatedAt: (now | todateiso8601),
    retryTransitions: count_by_status_change("retrying"),
    ciFailedTransitions: count_by_status_change("ci_failed"),
    readyForReviewTransitions: count_by_status_change("ready_for_review"),
    queueTransitions: count_by_event("task_queued"),
    runTimeouts: count_timeout("run_timeout"),
    queueTimeouts: count_timeout("queue_timeout"),
    totalEvents: (event_list | length)
  }')"

queue_stats="$(for d in active completed failed stopped; do
  dir="$ROOT/tasks/$d"
  [[ -d "$dir" ]] || continue
  for f in "$dir"/*.json; do
    [[ -f "$f" ]] || continue
    jq -r '
      (.queuedAt // empty) as $q
      | (.startedAt // empty) as $s
      | if ($q != "" and $s != "") then [$q,$s] | @tsv else empty end
    ' "$f"
  done
done | awk -F'\t' '
  function to_epoch(cmd, v, out) {
    gsub(/"/, "", v);
    cmd = "date -d \"" v "\" +%s 2>/dev/null";
    cmd | getline out;
    close(cmd);
    return out + 0;
  }
  {
    qs=to_epoch("", $1, "");
    ss=to_epoch("", $2, "");
    if (qs > 0 && ss > 0 && ss >= qs) {
      sum += (ss - qs);
      n += 1;
    }
  }
  END {
    if (n == 0) {
      print "0\t0";
    } else {
      printf "%.2f\t%d\n", sum / n, n;
    }
  }')"

avg_queue_seconds="$(awk -F'\t' '{print $1}' <<< "$queue_stats")"
queue_samples="$(awk -F'\t' '{print $2}' <<< "$queue_stats")"

completed_24h="$(for f in "$ROOT/tasks/completed"/*.json; do
  [[ -f "$f" ]] || continue
  jq -r '.completedAt // empty' "$f"
done | awk -v cutoff="$CUTOFF_EPOCH" '
  function to_epoch(v, cmd, out) {
    gsub(/"/, "", v);
    cmd = "date -d \"" v "\" +%s 2>/dev/null";
    cmd | getline out;
    close(cmd);
    return out + 0;
  }
  {
    e=to_epoch($0, "", "");
    if (e >= cutoff) c += 1;
  }
  END { print c + 0 }')"

status_counts_json="$(for d in active completed failed stopped; do
  dir="$ROOT/tasks/$d"
  [[ -d "$dir" ]] || continue
  for f in "$dir"/*.json; do
    [[ -f "$f" ]] || continue
    jq -c '.status // "unknown"' "$f"
  done
done | jq -s 'group_by(.) | map({status:.[0],count:length})')"

final_json="$(jq -cn \
  --argjson base "$metrics_json" \
  --argjson avgQ "$avg_queue_seconds" \
  --argjson qn "$queue_samples" \
  --argjson completed "$completed_24h" \
  --argjson statuses "$status_counts_json" '
  $base + {
    avgQueueSeconds: $avgQ,
    avgQueueSamples: $qn,
    completedInWindow: $completed,
    statusCounts: $statuses
  }')"

if [[ "$OUTPUT_JSON" -eq 1 ]]; then
  jq . <<< "$final_json"
  exit 0
fi

echo "OpenClaw Optimizer Metrics"
echo "window_hours=$WINDOW_HOURS generated_at=$(jq -r '.generatedAt' <<< "$final_json")"
echo "retry_transitions=$(jq -r '.retryTransitions' <<< "$final_json")"
echo "ci_failed_transitions=$(jq -r '.ciFailedTransitions' <<< "$final_json")"
echo "ready_for_review_transitions=$(jq -r '.readyForReviewTransitions' <<< "$final_json")"
echo "queue_transitions=$(jq -r '.queueTransitions' <<< "$final_json")"
echo "run_timeouts=$(jq -r '.runTimeouts' <<< "$final_json")"
echo "queue_timeouts=$(jq -r '.queueTimeouts' <<< "$final_json")"
echo "avg_queue_seconds=$(jq -r '.avgQueueSeconds' <<< "$final_json") samples=$(jq -r '.avgQueueSamples' <<< "$final_json")"
echo "completed_in_window=$(jq -r '.completedInWindow' <<< "$final_json")"
echo "total_events=$(jq -r '.totalEvents' <<< "$final_json")"
echo "status_counts=$(jq -c '.statusCounts' <<< "$final_json")"
