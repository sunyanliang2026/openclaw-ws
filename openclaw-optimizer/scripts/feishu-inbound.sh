#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/ubuntu/.openclaw/workspace/openclaw-optimizer"
RUNTIME="$ROOT/runtime"
PID_FILE="$RUNTIME/state/feishu-inbound.pid"
LOG_FILE="$RUNTIME/logs/feishu-inbound-daemon.log"
SERVER="$ROOT/scripts/feishu-inbound-server.py"

usage() {
  echo "Usage: $0 {start|stop|restart|status}"
}

mkdir -p "$RUNTIME/state" "$RUNTIME/logs"

is_running() {
  if [[ -f "$PID_FILE" ]]; then
    pid="$(cat "$PID_FILE" 2>/dev/null || true)"
    [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null
    return $?
  fi
  return 1
}

start() {
  if is_running; then
    echo "feishu inbound already running pid=$(cat "$PID_FILE")"
    return 0
  fi
  nohup python3 "$SERVER" >> "$LOG_FILE" 2>&1 &
  echo "$!" > "$PID_FILE"
  sleep 0.3
  if is_running; then
    echo "started feishu inbound pid=$(cat "$PID_FILE")"
  else
    echo "failed to start feishu inbound"
    exit 1
  fi
}

stop() {
  if ! is_running; then
    echo "feishu inbound not running"
    rm -f "$PID_FILE"
    return 0
  fi
  pid="$(cat "$PID_FILE")"
  kill "$pid" 2>/dev/null || true
  sleep 0.2
  rm -f "$PID_FILE"
  echo "stopped feishu inbound"
}

status() {
  if is_running; then
    echo "running pid=$(cat "$PID_FILE")"
  else
    echo "not running"
  fi
}

case "${1:-}" in
  start) start ;;
  stop) stop ;;
  restart) stop; start ;;
  status) status ;;
  *) usage; exit 1 ;;
esac
