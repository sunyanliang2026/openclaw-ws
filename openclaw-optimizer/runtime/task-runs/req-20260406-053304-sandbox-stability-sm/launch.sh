#!/usr/bin/env bash
set -euo pipefail
set -o pipefail
cd "/home/ubuntu/.openclaw/workspace/worktrees/req-20260406-053304-sandbox-stability-sm"
bash -lc codex\ exec\ --dangerously-bypass-approvals-and-sandbox\ 对\\\ internal-openclaw\\\ 做一次最小\\\ smoke：只运行\\\ pwd\\\ 和\\\ git\\\ status\\\ -sb，并输出命令与结果。 2>&1 | tee -a /home/ubuntu/.openclaw/workspace/openclaw-optimizer/runtime/task-runs/req-20260406-053304-sandbox-stability-sm/run.log
exit_code=${PIPESTATUS[0]}
jq -cn \
  --arg ts "$(date -Is)" \
  --argjson exitCode "$exit_code" \
  --arg cmd "codex exec --dangerously-bypass-approvals-and-sandbox 对\ internal-openclaw\ 做一次最小\ smoke：只运行\ pwd\ 和\ git\ status\ -sb，并输出命令与结果。" \
  '{finishedAt:$ts,exitCode:$exitCode,command:$cmd}' > /home/ubuntu/.openclaw/workspace/openclaw-optimizer/runtime/task-runs/req-20260406-053304-sandbox-stability-sm/exit.json
exit "$exit_code"
