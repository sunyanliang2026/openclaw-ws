#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME_ROOT="$ROOT_DIR/runtime"
REPO_PATH="${OPENCLAW_HEALTHCHECK_REPO:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      REPO_PATH="${2:-}"
      shift 2
      ;;
    --runtime)
      RUNTIME_ROOT="${2:-}"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [--repo <repo_path>] [--runtime <runtime_root>]"
      exit 0
      ;;
    *)
      echo "unknown arg: $1"
      exit 1
      ;;
  esac
done

if [[ -z "$REPO_PATH" ]]; then
  if git -C "$PWD" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    REPO_PATH="$(git -C "$PWD" rev-parse --show-toplevel)"
  elif git -C "$ROOT_DIR/.." rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    REPO_PATH="$(git -C "$ROOT_DIR/.." rev-parse --show-toplevel)"
  else
    REPO_PATH=""
  fi
fi

ok_count=0
warn_count=0
fail_count=0

ok() {
  ok_count=$((ok_count + 1))
  printf 'OK   %-14s %s\n' "$1" "$2"
}

warn() {
  warn_count=$((warn_count + 1))
  printf 'WARN %-14s %s\n' "$1" "$2"
}

fail() {
  fail_count=$((fail_count + 1))
  printf 'FAIL %-14s %s\n' "$1" "$2"
}

section() {
  printf '\n[%s]\n' "$1"
}

section "auth"
if command -v codex >/dev/null 2>&1; then
  auth_out="$(codex login status 2>&1 || true)"
  if grep -qi "Logged in" <<< "$auth_out"; then
    ok "codex" "$(tr '\n' ' ' <<< "$auth_out" | sed -E 's/[[:space:]]+/ /g')"
  else
    fail "codex" "$(tr '\n' ' ' <<< "$auth_out" | sed -E 's/[[:space:]]+/ /g')"
  fi
else
  fail "codex" "binary not found"
fi

section "gateway+feishu"
if command -v openclaw >/dev/null 2>&1; then
  probe_out="$(openclaw channels status --probe 2>&1 || true)"
  if grep -q "Gateway reachable" <<< "$probe_out"; then
    ok "gateway" "reachable"
  else
    fail "gateway" "not reachable"
  fi

  if grep -Eq "Feishu main: .*works" <<< "$probe_out"; then
    ok "feishu-main" "configured and working"
  elif grep -Eq "Feishu main: .*running" <<< "$probe_out"; then
    warn "feishu-main" "running but probe not confirmed as works"
  else
    fail "feishu-main" "not healthy"
  fi
else
  fail "openclaw" "binary not found"
fi

section "ports"
if command -v ss >/dev/null 2>&1; then
  ss_out="$(ss -ltnp 2>/dev/null || true)"
  if grep -Eq '127\.0\.0\.1:18789|::1:18789' <<< "$ss_out"; then
    ok "port-18789" "openclaw gateway listener present"
  else
    fail "port-18789" "openclaw gateway listener missing"
  fi

  if grep -Eq '0\.0\.0\.0:22|:::22' <<< "$ss_out"; then
    ok "port-22" "ssh listener present"
  else
    warn "port-22" "ssh listener not detected"
  fi

  if grep -Eq ':5901' <<< "$ss_out"; then
    ok "port-5901" "x11vnc listener present"
  else
    warn "port-5901" "x11vnc listener missing"
  fi

  if grep -Eq ':6080' <<< "$ss_out"; then
    ok "port-6080" "websockify listener present"
  else
    warn "port-6080" "websockify listener missing"
  fi
else
  fail "ports" "ss binary not found"
fi

section "memory+swap"
if command -v free >/dev/null 2>&1; then
  mem_total="$(free -m | awk '/^Mem:/ {print $2}')"
  mem_avail="$(free -m | awk '/^Mem:/ {print $7}')"
  swap_total="$(free -m | awk '/^Swap:/ {print $2}')"
  swap_used="$(free -m | awk '/^Swap:/ {print $3}')"

  if [[ "$mem_total" =~ ^[0-9]+$ ]] && [[ "$mem_avail" =~ ^[0-9]+$ ]] && (( mem_total > 0 )); then
    mem_avail_pct=$(( mem_avail * 100 / mem_total ))
    if (( mem_avail_pct < 15 )); then
      fail "memory" "available=${mem_avail}MB (${mem_avail_pct}%)"
    elif (( mem_avail_pct < 30 )); then
      warn "memory" "available=${mem_avail}MB (${mem_avail_pct}%)"
    else
      ok "memory" "available=${mem_avail}MB (${mem_avail_pct}%)"
    fi
  else
    fail "memory" "unable to parse free -m output"
  fi

  if [[ ! "$swap_total" =~ ^[0-9]+$ ]] || [[ ! "$swap_used" =~ ^[0-9]+$ ]]; then
    fail "swap" "unable to parse free -m output"
  elif (( swap_total <= 0 )); then
    fail "swap" "disabled"
  else
    swap_used_pct=$(( swap_used * 100 / swap_total ))
    if (( swap_used_pct > 60 )); then
      warn "swap" "used=${swap_used}MB/${swap_total}MB (${swap_used_pct}%)"
    else
      ok "swap" "used=${swap_used}MB/${swap_total}MB (${swap_used_pct}%)"
    fi
  fi
else
  fail "memory" "free binary not found"
fi

section "git"
if command -v git >/dev/null 2>&1; then
  if [[ -n "$REPO_PATH" ]] && [[ -d "$REPO_PATH/.git" ]]; then
    git_out="$(git -C "$REPO_PATH" status --porcelain 2>/dev/null || true)"
    branch_out="$(git -C "$REPO_PATH" status -sb 2>/dev/null || true)"
    if [[ -z "$git_out" ]]; then
      ok "git" "$(tr '\n' ' ' <<< "$branch_out" | sed -E 's/[[:space:]]+/ /g')"
    else
      warn "git" "working tree not clean"
    fi
  else
    warn "git" "no default repo detected (use --repo <path>)"
  fi
else
  fail "git" "binary not found"
fi

section "summary"
printf 'OK=%d WARN=%d FAIL=%d\n' "$ok_count" "$warn_count" "$fail_count"

if (( fail_count > 0 )); then
  exit 2
fi

exit 0
