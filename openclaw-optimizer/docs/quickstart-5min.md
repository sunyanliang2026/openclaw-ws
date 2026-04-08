# OpenClaw Optimizer 5分钟上手

## 1) 初始化（只做一次）

```bash
cd /home/ubuntu/.openclaw/workspace/openclaw-optimizer
./scripts/install-cron.sh
crontab -l
```

预期会看到 4 个定时任务：
- reconcile（每10分钟）
- pr-check（每10分钟，错峰）
- cleanup-worktrees（每小时）
- alert-check（每小时）

## 2) 创建一个任务

```bash
cp config/task-schema.example.json runtime/tasks/active/<task_id>.json
```

至少填这些字段：
- `id`
- `repoPath`
- `branch`
- `worktreePath`
- `launch.command`
- `launch.initialPrompt`

## 3) 启动任务

先预检：

```bash
./scripts/start-task.sh --dry-run <task_id>
```

再正式启动：

```bash
./scripts/start-task.sh <task_id>
```

## 4) 看进度与状态

```bash
./scripts/task-status.sh
./scripts/reconcile-tasks.sh
./scripts/pr-check.sh
```

常见状态含义：
- `queued`：并发满，排队中
- `running`：执行中
- `retrying`：按失败策略等待重试
- `ready_for_review`：通过门禁，等人工review
- `needs_update`：门禁未过，需要补充/修复

补充：
- `queued` 不需要手工干预，`reconcile` 会在资源可用时自动重试启动。

## 5) 查看指标与告警

```bash
./scripts/metrics-report.sh --hours 24 --json
./scripts/alert-check.sh
```

## 6) 收尾与清理

停止并归档：

```bash
./scripts/stop-task.sh --result stopped <task_id>
```

清理孤儿 worktree（先演练再执行）：

```bash
DRY_RUN=1 ./scripts/cleanup-worktrees.sh
./scripts/cleanup-worktrees.sh
```

## 7) 两个高频排障

- 一直 `queued`：检查 `config/concurrency.json` 的 `maxConcurrentAgents`。
- 一直 `retrying`：检查任务里的 `nextRetryAtEpoch` 和 `config/failure-policies.json`。
