#!/usr/bin/env bash
set -euo pipefail
set -o pipefail
cd "/home/ubuntu/.openclaw/workspace/worktrees/req-20260406-052850-smoke-from-feishu-no"
bash -lc codex\ exec\ --full-auto\ --sandbox\ danger-full-access\ \$\'对\ internal-openclaw\ 做一次\ smoke\ test，检查服务是否能启动、核心接口是否返回\ 2xx，并输出测试结果与失败项。\\n\\nRetry\ context:\\n-\ attempt:\ 1\\n-\ failure:\ tmux_session_not_alive\\n-\ class:\ infra\\n-\ guidance:\ Execution\ ended\ unexpectedly.\ Use\ smaller\ checkpoints\,\ log\ progress\ every\ 2-3\ steps\,\ and\ verify\ after\ each\ checkpoint.\\n\\nConstraints:\\n-\ Do\ not\ break\ current\ frontend\ API\ contract\\n-\ Add\ regression\ tests\ for\ error\ responses\\n\\nSuccess\ criteria:\\n-\ lint\ passes\\n-\ tests\ pass\\n-\ PR\ includes\ before/after\ behavior\ summary\\n\\nOutput\ requirement:\\n-\ End\ with\ exact\ commands\ run\ and\ pass/fail\ results.\' 2>&1 | tee -a /home/ubuntu/.openclaw/workspace/openclaw-optimizer/runtime/task-runs/req-20260406-052850-smoke-from-feishu-no/run.log
exit_code=${PIPESTATUS[0]}
jq -cn \
  --arg ts "$(date -Is)" \
  --argjson exitCode "$exit_code" \
  --arg cmd "codex exec --full-auto --sandbox danger-full-access $'对 internal-openclaw 做一次 smoke test，检查服务是否能启动、核心接口是否返回 2xx，并输出测试结果与失败项。\n\nRetry context:\n- attempt: 1\n- failure: tmux_session_not_alive\n- class: infra\n- guidance: Execution ended unexpectedly. Use smaller checkpoints, log progress every 2-3 steps, and verify after each checkpoint.\n\nConstraints:\n- Do not break current frontend API contract\n- Add regression tests for error responses\n\nSuccess criteria:\n- lint passes\n- tests pass\n- PR includes before/after behavior summary\n\nOutput requirement:\n- End with exact commands run and pass/fail results.'" \
  '{finishedAt:$ts,exitCode:$exitCode,command:$cmd}' > /home/ubuntu/.openclaw/workspace/openclaw-optimizer/runtime/task-runs/req-20260406-052850-smoke-from-feishu-no/exit.json
exit "$exit_code"
