#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="/home/ubuntu/.openclaw/workspace/openclaw-optimizer"
AGENT_DIR="$ROOT_DIR/config/agents"
SKILL_REGISTRY="$ROOT_DIR/config/skills/registry.json"
PROJECT_DIR="$ROOT_DIR/projects"
ROUTING_CONFIG="$ROOT_DIR/config/agent-selection.json"

STRICT_PATHS=0

usage() {
  cat <<USAGE
Usage:
  $0 [--strict-paths]

Checks:
  - config/agents/*.json
  - config/skills/registry.json
  - projects/*.json
  - config/agent-selection.json (agent references)
USAGE
}

require_bin() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing binary: $1"
    exit 1
  }
}

require_bin jq

while [[ $# -gt 0 ]]; do
  case "$1" in
    --strict-paths)
      STRICT_PATHS=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown arg: $1"
      usage
      exit 1
      ;;
  esac
done

errors=0
warnings=0

err() {
  echo "ERROR: $*"
  errors=$((errors + 1))
}

warn() {
  echo "WARN: $*"
  warnings=$((warnings + 1))
}

declare -A AGENTS=()
declare -A SKILLS=()

if [[ ! -d "$AGENT_DIR" ]]; then
  err "agent dir missing: $AGENT_DIR"
else
  shopt -s nullglob
  agent_files=("$AGENT_DIR"/*.json)
  if (( ${#agent_files[@]} == 0 )); then
    err "no agent profiles found in $AGENT_DIR"
  fi
  for f in "${agent_files[@]}"; do
    if ! jq -e . "$f" >/dev/null 2>&1; then
      err "invalid json: $f"
      continue
    fi
    id="$(jq -r '.id // empty' "$f")"
    launch_cmd="$(jq -r '.launch.command // empty' "$f")"
    if [[ -z "$id" ]]; then
      err "agent id missing: $f"
      continue
    fi
    if [[ -z "$launch_cmd" ]]; then
      err "agent launch.command missing: $f"
    fi
    base="$(basename "$f" .json)"
    if [[ "$base" != "$id" ]]; then
      warn "agent file name != id: $f (id=$id)"
    fi
    AGENTS["$id"]=1
  done
fi

if [[ ! -f "$SKILL_REGISTRY" ]]; then
  err "skill registry missing: $SKILL_REGISTRY"
else
  if ! jq -e . "$SKILL_REGISTRY" >/dev/null 2>&1; then
    err "invalid json: $SKILL_REGISTRY"
  else
    if ! jq -e '.skills | type == "array"' "$SKILL_REGISTRY" >/dev/null 2>&1; then
      err "skills array missing: $SKILL_REGISTRY"
    fi
    while IFS= read -r sid; do
      [[ -z "$sid" ]] && continue
      SKILLS["$sid"]=1
    done < <(jq -r '.skills[]?.id // empty' "$SKILL_REGISTRY")
  fi
fi

if [[ ! -d "$PROJECT_DIR" ]]; then
  err "project dir missing: $PROJECT_DIR"
else
  shopt -s nullglob
  project_files=("$PROJECT_DIR"/*.json)
  if (( ${#project_files[@]} == 0 )); then
    warn "no project manifests found in $PROJECT_DIR"
  fi
  for f in "${project_files[@]}"; do
    if ! jq -e . "$f" >/dev/null 2>&1; then
      err "invalid json: $f"
      continue
    fi
    for k in id name repoPath baseBranch worktreeRoot defaultTaskType defaultPriority defaultAgent; do
      v="$(jq -r --arg k "$k" '.[$k] // empty' "$f")"
      if [[ -z "$v" ]]; then
        err "project field missing ($k): $f"
      fi
    done

    pa="$(jq -r '.defaultAgent // empty' "$f")"
    if [[ -n "$pa" && -z "${AGENTS[$pa]:-}" ]]; then
      err "project references unknown defaultAgent=$pa: $f"
    fi

    while IFS= read -r skill_id; do
      [[ -z "$skill_id" ]] && continue
      if [[ -z "${SKILLS[$skill_id]:-}" ]]; then
        err "project references unknown skill=$skill_id: $f"
      fi
    done < <(jq -r '.defaultSkills[]? // empty' "$f")

    repo_path="$(jq -r '.repoPath // empty' "$f")"
    if [[ -n "$repo_path" && ! -d "$repo_path" ]]; then
      if (( STRICT_PATHS == 1 )); then
        err "repoPath not found: $repo_path ($f)"
      else
        warn "repoPath not found: $repo_path ($f)"
      fi
    fi
  done
fi

if [[ -f "$ROUTING_CONFIG" ]]; then
  if ! jq -e . "$ROUTING_CONFIG" >/dev/null 2>&1; then
    err "invalid json: $ROUTING_CONFIG"
  else
    while IFS= read -r a; do
      [[ -z "$a" ]] && continue
      if [[ -z "${AGENTS[$a]:-}" ]]; then
        err "routing references unknown primary agent=$a in $ROUTING_CONFIG"
      fi
    done < <(jq -r '.routing[]?.primary // empty' "$ROUTING_CONFIG")
  fi
fi

echo "validate-manifests: errors=$errors warnings=$warnings"
if (( errors > 0 )); then
  exit 1
fi

