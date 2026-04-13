#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: apply-feishu-brain-capture-patch.sh [--apply|--status|--restore] [--restart] [--target-file <path>]

Options:
  --apply               Apply the Feishu brain-capture patch if missing.
  --status              Report whether the target file is already patched. Default.
  --restore             Restore the target file from the saved backup.
  --restart             Restart openclaw-gateway after apply/restore.
  --target-file <path>  Patch a specific monitor-*.js file instead of auto-detecting.
  -h, --help            Show this help.
EOF
}

ACTION="status"
RESTART=0
TARGET_FILE=""
DIST_DIR="/home/ubuntu/.local/lib/node_modules/openclaw/dist"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply)
      ACTION="apply"
      shift
      ;;
    --status)
      ACTION="status"
      shift
      ;;
    --restore)
      ACTION="restore"
      shift
      ;;
    --restart)
      RESTART=1
      shift
      ;;
    --target-file)
      TARGET_FILE="${2:-}"
      shift 2
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

require_bin() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing binary: $1" >&2
    exit 1
  }
}

resolve_target_file() {
  if [[ -n "$TARGET_FILE" ]]; then
    printf '%s\n' "$TARGET_FILE"
    return 0
  fi

  rg -l --glob 'monitor-*.js' \
    'function createFeishuReplyDispatcher\(params\)' \
    "$DIST_DIR" \
    | head -n 1
}

print_status() {
  local target_file="$1"
  TARGET="$target_file" node <<'EOF'
const fs = require("node:fs");

const target = process.env.TARGET;
const text = fs.readFileSync(target, "utf8");
const patched =
  text.includes('import { execFile } from "node:child_process";') &&
  text.includes("function maybeCaptureFeishuTurnToBrain(params)") &&
  text.includes('getDeliveredFinalText: () => Array.from(deliveredFinalTexts).join("\\n\\n").trim()') &&
  text.includes("const { dispatcher, replyOptions, markDispatchIdle, getDeliveredFinalText } = createFeishuReplyDispatcher({") &&
  text.includes("maybeCaptureFeishuTurnToBrain({") &&
  text.includes("replyText: getDeliveredFinalText()");

console.log(JSON.stringify({ target, patched }));
process.exit(patched ? 0 : 1);
EOF
}

apply_patch_to_file() {
  local target_file="$1"
  TARGET="$target_file" node <<'EOF'
const fs = require("node:fs");

const target = process.env.TARGET;
const original = fs.readFileSync(target, "utf8");
let text = original;

const importNeedle = 'import crypto from "node:crypto";\n';
const importPatch = 'import crypto from "node:crypto";\nimport { execFile } from "node:child_process";\n';

const helperNeedle = `function buildBroadcastSessionKey(baseSessionKey, originalAgentId, targetAgentId) {
\tconst prefix = \`agent:\${originalAgentId}:\`;
\tif (baseSessionKey.startsWith(prefix)) return \`agent:\${targetAgentId}:\${baseSessionKey.slice(prefix.length)}\`;
\treturn baseSessionKey;
}
`;

const helperPatch = `function buildBroadcastSessionKey(baseSessionKey, originalAgentId, targetAgentId) {
\tconst prefix = \`agent:\${originalAgentId}:\`;
\tif (baseSessionKey.startsWith(prefix)) return \`agent:\${targetAgentId}:\${baseSessionKey.slice(prefix.length)}\`;
\treturn baseSessionKey;
}
function maybeCaptureFeishuTurnToBrain(params) {
\tconst { cfg, log, ctx, replyText } = params;
\tif (!replyText || !replyText.trim()) return;
\tconst scriptPath = "/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/capture-feishu-turn-to-brain.sh";
\tif (!fsSync.existsSync(scriptPath)) {
\t\tlog(\`feishu: brain capture script missing at \${scriptPath}\`);
\t\treturn;
\t}
\tconst args = ["--message", ctx.content, "--reply", replyText, "--chat-id", ctx.chatId];
\targs.push("--project", "internal-openclaw");
\texecFile(scriptPath, args, {
\t\tenv: process.env,
\t\tmaxBuffer: 1024 * 1024
\t}, (error, stdout, stderr) => {
\t\tif (error) {
\t\t\tlog(\`feishu: brain capture failed for \${ctx.chatId}: \${String(error)}\`);
\t\t\treturn;
\t\t}
\t\tconst output = [stdout, stderr].filter(Boolean).map((value) => value.trim()).filter(Boolean).join(" | ");
\t\tif (output) log(\`feishu: brain capture result for \${ctx.chatId}: \${output}\`);
\t});
}
`;

const getterNeedle = `\t\tmarkDispatchIdle
\t};
`;

const getterPatch = `\t\tmarkDispatchIdle,
\t\tgetDeliveredFinalText: () => Array.from(deliveredFinalTexts).join("\\n\\n").trim()
\t};
`;

const destructureNeedle = "const { dispatcher, replyOptions, markDispatchIdle } = createFeishuReplyDispatcher({";
const destructurePatch = "const { dispatcher, replyOptions, markDispatchIdle, getDeliveredFinalText } = createFeishuReplyDispatcher({";

const captureNeedle = `\t\t\tif (isGroup && historyKey && chatHistories) clearHistoryEntriesIfEnabled({
\t\t\t\thistoryMap: chatHistories,
\t\t\t\thistoryKey,
\t\t\t\tlimit: historyLimit
\t\t\t});
\t\t\tlog(\`feishu[\${account.accountId}]: dispatch complete (queuedFinal=\${queuedFinal}, replies=\${counts.final})\`);
`;

const capturePatch = `\t\t\tif (isGroup && historyKey && chatHistories) clearHistoryEntriesIfEnabled({
\t\t\t\thistoryMap: chatHistories,
\t\t\t\thistoryKey,
\t\t\t\tlimit: historyLimit
\t\t\t});
\t\t\tmaybeCaptureFeishuTurnToBrain({
\t\t\t\tcfg,
\t\t\t\tlog,
\t\t\t\tctx,
\t\t\t\treplyText: getDeliveredFinalText()
\t\t\t});
\t\t\tlog(\`feishu[\${account.accountId}]: dispatch complete (queuedFinal=\${queuedFinal}, replies=\${counts.final})\`);
`;

function replaceOnce(src, needle, patch, label) {
  if (src.includes(patch)) return src;
  if (!src.includes(needle)) {
    throw new Error(`patch anchor not found: ${label}`);
  }
  return src.replace(needle, patch);
}

text = replaceOnce(text, importNeedle, importPatch, "import");
text = replaceOnce(text, helperNeedle, helperPatch, "helper");
text = replaceOnce(text, getterNeedle, getterPatch, "getter");
text = replaceOnce(text, destructureNeedle, destructurePatch, "destructure");
text = replaceOnce(text, captureNeedle, capturePatch, "capture-call");

if (text === original) {
  console.log(JSON.stringify({ target, changed: false, patched: true }));
  process.exit(0);
}

fs.writeFileSync(target, text);
console.log(JSON.stringify({ target, changed: true, patched: true }));
EOF
}

restore_backup() {
  local target_file="$1"
  local backup_file="$2"
  if [[ ! -f "$backup_file" ]]; then
    echo "backup not found: $backup_file" >&2
    exit 1
  fi
  cp "$backup_file" "$target_file"
}

restart_gateway() {
  systemctl --user restart openclaw-gateway
  systemctl --user is-active openclaw-gateway >/dev/null
}

require_bin rg
require_bin node

TARGET_FILE="$(resolve_target_file)"
if [[ -z "$TARGET_FILE" || ! -f "$TARGET_FILE" ]]; then
  echo "unable to locate target monitor file" >&2
  exit 1
fi

BACKUP_FILE="${TARGET_FILE}.feishu-brain-capture.bak"

case "$ACTION" in
  status)
    print_status "$TARGET_FILE"
    ;;
  apply)
    if [[ ! -f "$BACKUP_FILE" ]]; then
      cp "$TARGET_FILE" "$BACKUP_FILE"
    fi
    apply_patch_to_file "$TARGET_FILE"
    node --check "$TARGET_FILE"
    if [[ "$RESTART" -eq 1 ]]; then
      restart_gateway
    fi
    ;;
  restore)
    restore_backup "$TARGET_FILE" "$BACKUP_FILE"
    node --check "$TARGET_FILE"
    if [[ "$RESTART" -eq 1 ]]; then
      restart_gateway
    fi
    ;;
esac
