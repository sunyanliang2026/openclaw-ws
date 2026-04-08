#!/usr/bin/env bash
set -euo pipefail

SCRIPT="/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/reconcile-tasks.sh"
PR_CHECK_SCRIPT="/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/pr-check.sh"
CLEANUP_SCRIPT="/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/cleanup-worktrees.sh"
ALERT_SCRIPT="/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/alert-check.sh"
RUNTIME_ROOT="/home/ubuntu/.openclaw/workspace/openclaw-optimizer/runtime"
ENTRY="*/10 * * * * $SCRIPT $RUNTIME_ROOT >> $RUNTIME_ROOT/logs/reconcile-cron.log 2>&1"
PR_ENTRY="5-59/10 * * * * $PR_CHECK_SCRIPT $RUNTIME_ROOT >> $RUNTIME_ROOT/logs/pr-check-cron.log 2>&1"
CLEANUP_ENTRY="17 * * * * $CLEANUP_SCRIPT $RUNTIME_ROOT >> $RUNTIME_ROOT/logs/cleanup-cron.log 2>&1"
ALERT_ENTRY="27 * * * * $ALERT_SCRIPT $RUNTIME_ROOT >> $RUNTIME_ROOT/logs/alert-cron.log 2>&1"

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

if crontab -l >"$TMP" 2>/dev/null; then
  :
else
  : >"$TMP"
fi

if ! grep -Fqx "$ENTRY" "$TMP"; then
  printf '%s\n' "$ENTRY" >>"$TMP"
fi

if ! grep -Fqx "$PR_ENTRY" "$TMP"; then
  printf '%s\n' "$PR_ENTRY" >>"$TMP"
fi

if ! grep -Fqx "$CLEANUP_ENTRY" "$TMP"; then
  printf '%s\n' "$CLEANUP_ENTRY" >>"$TMP"
fi

if ! grep -Fqx "$ALERT_ENTRY" "$TMP"; then
  printf '%s\n' "$ALERT_ENTRY" >>"$TMP"
fi

crontab "$TMP"

crontab -l
