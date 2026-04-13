# OpenClaw Optimizer 使用说明

本文是当前版本（已含并发控制、非阻塞重试、SLA、质量门禁、指标与告警、FailureClass 路由）的操作手册。

> 快速上手：先看 `docs/quickstart-5min.md`（5 分钟）。

## 1. 目录与角色

- `config/`
  - `agents/*.json`：Agent 配置目录（新增 Agent 只需加文件）
  - `skills/registry.json`：Skill 注册表
  - `concurrency.json`：并发与资源策略
  - `quality-gates.json`：PR 质量门禁（含 mergeable/behind）
  - `failure-policies.json`：失败分类重试策略
  - `alerts.json`：告警阈值与通知配置
  - `inbound-feishu.json`：飞书入站任务桥接配置
  - `task-schema.example.json`：任务 JSON 模板
- `scripts/`
  - `start-task.sh`：启动任务（worktree + tmux + agent）
  - `feishu-command-dispatch.sh`：解析飞书 `/newtask` 指令并派发任务
  - `reconcile-tasks.sh`：状态协调、超时治理、重试调度
  - `pr-check.sh`：PR/CI/门禁检查
  - `adjust-prompt.sh`：按失败分类重写重试 prompt
- `metrics-report.sh`：窗口指标统计
- `alert-check.sh`：阈值告警检查（可通知）
- `cleanup-worktrees.sh`：孤儿 worktree 清理
- `sync-task-summary-to-brain.sh`：将任务摘要 JSON 转成 brain markdown 并导入 gbrain
- `capture-brain-note.sh`：把普通问答/直接 Codex 会话摘要写入 brain
- `codex-brain-exec.sh`：包装 `codex exec`，自动把最终结论写入 brain
- `brain-first-agent.sh`：本地问答入口，先查 `gbrain` 再把上下文交给 `openclaw agent`
- `capture-feishu-turn-to-brain.sh`：普通 Feishu 问答的 durable-signal 摘要写入器；现已被 live gateway 自动调用
- `feishu-turn-wrapper.sh`：本地测试或手工驱动 Feishu turn 的统一入口
- `apply-feishu-brain-capture-patch.sh`：在 OpenClaw 升级后，重新把普通 Feishu 问答自动入脑补丁打回 live gateway monitor
- `install-cron.sh`：安装定时任务
- `feishu-inbound-server.py`：飞书 HTTP 入站服务（备用）
- `feishu-inbound.sh`：HTTP 入站服务启停管理（备用）
- `runtime/`
  - `tasks/{active,completed,failed,stopped}`
  - `logs/*.log`
  - `events/*events-YYYYMMDD.jsonl`
  - `state/*.json`
- `projects/`
  - `*.json`：项目级配置（repo、默认 agent/type/priority、约束、成功标准）
- `templates/`
  - `project.example.json`
  - `requirement.example.md`

## 2. 首次初始化

```bash
cd /home/ubuntu/.openclaw/workspace/openclaw-optimizer
/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/install-cron.sh
```

确认 cron 已安装：

```bash
crontab -l
```

默认会安装：

- 每 10 分钟 `reconcile-tasks.sh`
- 每 10 分钟（错峰）`pr-check.sh`
- 每小时 `cleanup-worktrees.sh`
- 每小时 `alert-check.sh`

## 3. 新建任务

0) （推荐）先建项目配置：

```bash
/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/new-project.sh \
  --id my-project \
  --name "My Project" \
  --repo /abs/path/to/repo
```

1) 复制模板：

```bash
cp /home/ubuntu/.openclaw/workspace/openclaw-optimizer/config/task-schema.example.json \
  /home/ubuntu/.openclaw/workspace/openclaw-optimizer/runtime/tasks/active/<task_id>.json
```

2) 填写关键字段：

- `id`
- `repoPath`
- `branch`
- `worktreePath`
- `launch.command`（默认可用 `codex exec --full-auto`）
- `launch.initialPrompt`
- `maxRunMinutes` / `maxQueueMinutes`（建议保留默认后按项目调）

3) 启动任务：

```bash
/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/start-task.sh <task_id>
```

或用脚手架按项目生成任务：

```bash
/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/new-task.sh \
  --project my-project \
  --task-id feat-my-first-task \
  --title "Implement API hardening for /detect/text"
```

仅预览（不执行）：

```bash
/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/start-task.sh --dry-run <task_id>
```

## 4. 任务生命周期

常见状态：

- `pending`：待启动
- `queued`：因并发限制入队（`queueReason=concurrency_limit`）
- `running`：执行中
- `retrying`：等待 `nextRetryAtEpoch` 到期后重启
- `ci_running`：PR checks 进行中
- `ready_for_review`：门禁通过，待人工 review
- `needs_update`：门禁不通过（PR 描述/验证信息/可合并性等）
- `ci_failed`：CI 失败
- `completed` / `failed` / `stopped`

说明：

- `reconcile` 会自动尝试拉起 `pending/queued` 任务；并发仍受 `concurrency.json` 限制。
- 到达非执行态（`ready_for_review/needs_update/ci_*`）后，`reconcile` 会回收对应 tmux 会话，避免资源泄漏。

手动跑一轮全流程：

```bash
/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/reconcile-tasks.sh
/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/pr-check.sh
```

并发安全：

- `reconcile-tasks.sh` 与 `start-task.sh` 都带文件锁，重叠触发时会自动跳过，避免重复启动同一任务。

查看状态汇总：

```bash
/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/task-status.sh
```

## 5. FailureClass 重试路由

失败分类见 `config/failure-policies.json`：

- `infra`
- `code`
- `ci`
- `auth`
- `rate_limit`
- `unknown`

每类可配置：

- `retryable`
- `maxAttempts`
- `backoffSeconds`

行为：

- `reconcile` 会分类并按策略决定是否重试。
- 不可重试类（默认 `ci/auth`）直接进入 `failed`。
- 可重试类进入 `retrying`，并写入 `nextRetryAtEpoch`。
- `adjust-prompt.sh` 按 `failureClass` 生成不同重试提示。

## 6. PR 质量门禁

`pr-check.sh` 会检查：

- PR 描述必需章节（默认 `Validation/Risk/Rollback`）
- 任务验证字段（默认 `verification.testCommand/testsPassed`）
- `requireMergeable`（是否可合并）
- `maxBehindCommits`（分支落后基线提交数上限）

不通过会设置：

- `status=needs_update`
- `qualityGate.issues=[...]`
- 可选自动评论 PR（配置项控制）

## 7. SLA 与稳定性策略

- `maxRunMinutes`：运行超时 -> `run_timeout`
- `maxQueueMinutes`：排队/重试超时 -> `queue_timeout`
- 非执行态（`ready_for_review/needs_update/ci_*`）若 tmux 丢失，只清理 `tmuxSession`，不会误触发重试。

## 8. 指标与告警

查看指标：

```bash
/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/metrics-report.sh
/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/metrics-report.sh --hours 48 --json
```

执行告警检查：

```bash
/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/alert-check.sh
```

阈值配置：`config/alerts.json`。

## 9. 告警通知配置

在 `config/alerts.json` 设置：

- `notifications.enabled`
- `notifications.cooldownMinutes`
- `notifications.timeoutSeconds`
- `notifications.feishuWebhook`
- `notifications.slackWebhook`
- `notifications.genericWebhook`

或使用环境变量覆盖：

- `ALERT_FEISHU_WEBHOOK`
- `ALERT_SLACK_WEBHOOK`
- `ALERT_GENERIC_WEBHOOK`
- `ALERT_GENERIC_BEARER`

说明：

- 同一告警指纹会按冷却窗口去重，状态存于 `runtime/state/alert-state.json`。
- 强制触发测试可用：`ALERT_FORCE_TRIGGER=1`。

## 9.5 GBrain 集成

任务摘要自动入脑：

- `write-task-summary.sh` 生成 `runtime/summaries/*.json` 后，会自动调用 `sync-task-summary-to-brain.sh`
- 目标目录：`/home/ubuntu/brain/projects/openclaw-tasks/`
- 入脑内容以任务摘要为主，`run.log` 仅保留路径和失败关键信号，不导入全文

手动全量补同步：

```bash
/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/sync-task-summary-to-brain.sh --all
```

普通飞书问答或直接 Codex CLI 会话，使用：

```bash
/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/capture-brain-note.sh \
  --source feishu \
  --title "示例标题" \
  --body "只写可复用结论，不写全文聊天记录。"
```

本地强制 brain-first 问答入口：

```bash
/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/brain-first-agent.sh \
  --message "What did we decide about Feishu auto-capture?" \
  --json
```

行为：

- 先执行 `gbrain ask`
- 再执行 `gbrain search`
- 把两段结果注入 agent prompt
- 最后调用 `openclaw agent`

普通 Feishu 问答自动入脑：

- live OpenClaw gateway 在发送最终回复后，会自动调用 `capture-feishu-turn-to-brain.sh`
- `/newtask` 仍然走 task dispatch，不走普通问答 capture
- capture 脚本仍会跳过 heartbeat、纯确认、过短无信号消息
- 目标目录：`/home/ubuntu/brain/inbox/feishu/`

如果 `openclaw update` 覆盖了安装目录里的 `monitor-*.js`，重新执行：

```bash
/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/apply-feishu-brain-capture-patch.sh --apply --restart
```

手动补记或测试 capture：

```bash
/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/capture-feishu-turn-to-brain.sh \
  --message "原始用户消息" \
  --reply "你已经发出去的回复" \
  --summary "1-3句 durable summary" \
  --chat-id oc_xxx \
  --project internal-openclaw \
  --durable-type decision
```

行为：

- 默认跳过 `/newtask`、heartbeat、纯确认消息、过短无信号的对话
- 只写摘要，不写全文 transcript
- 目标目录：`/home/ubuntu/brain/inbox/feishu/`

如果希望从本地 shell 人工驱动一轮 Feishu turn，再现线上同样的回复加 capture 逻辑，使用：

```bash
/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/feishu-turn-wrapper.sh \
  --chat-id oc_xxx \
  --message "原始用户消息" \
  --capture-summary "1-3句 durable summary" \
  --durable-type decision \
  --json
```

行为：

- `/newtask` 自动走 dispatch 并回发 receipt
- 普通问答自动调用 `openclaw agent --json`
- 自动把回复发回 Feishu
- 自动调用 `capture-feishu-turn-to-brain.sh`

详细边界与建议见：

- `docs/gbrain-integration.md`

直接 `codex exec` 时，优先使用包装脚本：

```bash
/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/codex-brain-exec.sh \
  --title "会话标题" \
  --project internal-openclaw \
  -- \
  codex exec -C /abs/repo "你的任务描述"
```

这样会：

- 保留运行日志到 `runtime/codex-cli-runs/`
- 自动抓取 `codex exec` 最后一条消息
- 写一条结构化 closeout 到 brain，而不是保存整段 transcript

## 10. 日常运维命令

停止并归档任务：

```bash
/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/stop-task.sh --result stopped <task_id>
```

停止但保留 worktree：

```bash
/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/stop-task.sh --keep-worktree --result stopped <task_id>
```

手动清理孤儿 worktree：

```bash
DRY_RUN=1 /home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/cleanup-worktrees.sh
/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/cleanup-worktrees.sh
```

校验结构配置（agent/skill/project/routing）：

```bash
/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/validate-manifests.sh
```

## 11. 故障排查

- 任务不启动：先跑 `start-task.sh --dry-run <task_id>` 看字段缺失。
- 一直 `queued`：检查 `concurrency.json` 的 `maxConcurrentAgents` 和现有 tmux 会话数。
- 一直 `retrying`：检查 `nextRetryAtEpoch` 是否还未到；看 `reconcile-events`。
- `needs_update`：查看 `qualityGate.issues` 与 PR 评论内容。
- 告警不通知：检查 `alerts.json.notifications.enabled`、webhook 地址、`runtime/events/alert-events-*` 和 `runtime/state/alert-state.json`。

## 12. 飞书 Websocket 指令派发（推荐）

在飞书对话中发送：

```text
/newtask
title: 做官网一期
project: internal-openclaw
type: frontend-feature
priority: high
start: true
prompt: 实现公司官网，含首页、产品页、联系页；支持移动端并补充基础测试。
```

本地派发器（供 Agent 调用）：

```bash
/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/feishu-command-dispatch.sh --text '<message>'
```

行为：
- 解析 `/newtask` 消息。
- 调用 `new-task.sh` 创建任务。
- `start=true` 时调用 `start-task.sh`。
- 事件写入 `runtime/events/feishu-command-events-*.jsonl`。

## 13. 飞书 HTTP 入站（备用）

1) 配置 `config/inbound-feishu.json`：
- `enabled=true`
- `authToken`（建议必填）
- `defaultProjectId`（例如 `internal-openclaw`）

2) 启动服务：

```bash
/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/feishu-inbound.sh start
/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/feishu-inbound.sh status
```

3) 将飞书回调地址配置为：
- `http://<host>:8787/feishu/webhook?token=<authToken>`

4) 消息建议格式（纯文本）：
```text
title: 做官网一期
project: internal-openclaw
type: frontend-feature
priority: high
实现一个公司官网，含首页、产品页、联系页；要求可部署、含基础测试。
```

5) 系统行为：
- 自动调用 `new-task.sh` 生成任务。
- `autoStart=true` 时自动调用 `start-task.sh` 启动执行。
- 事件写入 `runtime/events/feishu-inbound-events-*.jsonl`。
