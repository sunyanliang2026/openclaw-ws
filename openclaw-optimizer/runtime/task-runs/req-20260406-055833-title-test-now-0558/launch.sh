#!/usr/bin/env bash
set -euo pipefail
set -o pipefail
cd "/home/ubuntu/.openclaw/workspace/worktrees/req-20260406-055833-title-test-now-0558"
bash -lc codex\ exec\ --dangerously-bypass-approvals-and-sandbox\ \$\'\ title:\ test-now-0558\\n\ project:\ internal-openclaw\\n\ type:\ backend-feature\\n\ priority:\ low\\n\ start:\ true\\n\ prompt:\ 只做连通性测试，执行\ pwd\ 和\ git\ status\ -sb，回传结果。\' 2>&1 | tee -a /home/ubuntu/.openclaw/workspace/openclaw-optimizer/runtime/task-runs/req-20260406-055833-title-test-now-0558/run.log
exit_code=${PIPESTATUS[0]}
jq -cn \
  --arg ts "$(date -Is)" \
  --argjson exitCode "$exit_code" \
  --arg cmd "codex exec --dangerously-bypass-approvals-and-sandbox $' title: test-now-0558\n project: internal-openclaw\n type: backend-feature\n priority: low\n start: true\n prompt: 只做连通性测试，执行 pwd 和 git status -sb，回传结果。'" \
  '{finishedAt:$ts,exitCode:$exitCode,command:$cmd}' > /home/ubuntu/.openclaw/workspace/openclaw-optimizer/runtime/task-runs/req-20260406-055833-title-test-now-0558/exit.json
exit "$exit_code"
