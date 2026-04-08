# OpenClaw 结构升级说明

目标：让系统在不改核心调度脚本的前提下，能快速引入新 agent、skill、新项目和新需求。

## 1) 分层原则

- 调度层：`scripts/reconcile-tasks.sh`、`scripts/start-task.sh`、`scripts/pr-check.sh`
- 配置层：`config/*`
- 项目层：`projects/*.json`
- 任务层：`runtime/tasks/*`
- 观测层：`runtime/logs` + `runtime/events` + `runtime/state`

## 2) Agent 扩展（无代码变更）

在 `config/agents/<agent>.json` 新增配置：

```json
{
  "id": "new-agent",
  "model": "...",
  "capabilities": ["backend-feature"],
  "launch": {
    "command": "new-agent-cli run {{prompt}}"
  }
}
```

说明：`start-task.sh` 会优先读取该命令模板。
可用占位符：`{{prompt}}`、`{{task_id}}`、`{{branch}}`、`{{worktree}}`。

## 3) Skill 扩展

在 `config/skills/registry.json` 增加 skill 元数据，用于项目默认技能编排。

## 4) 项目扩展

用脚本创建项目清单：

```bash
./scripts/new-project.sh --id my-project --name "My Project" --repo /abs/path/repo
```

项目清单集中维护：
- 默认 task type / priority / agent
- 约束条件
- 成功标准
- 默认 skills

## 5) 需求到任务

先准备需求文档（可用 `templates/requirement.example.md`），再生成任务：

```bash
./scripts/new-task.sh \
  --project my-project \
  --task-id feat-abc \
  --title "Implement feature ABC" \
  --requirement templates/requirement.example.md
```

生成后会写入 `runtime/tasks/active/feat-abc.json`，可直接 `start-task.sh feat-abc`。

## 6) 兼容性

- 旧任务 JSON 仍可运行。
- `launch.command` 未显式提供时，才会回退到 agent profile/default。
- 指标脚本同时兼容 `runtime/events` 和历史 `runtime/logs/*events*`。

## 7) 结构一致性校验

```bash
./scripts/validate-manifests.sh
./scripts/validate-manifests.sh --strict-paths
```

会校验：
- agent profile 完整性
- routing 对 agent 的引用
- project 对 agent/skill 的引用
- skill registry 结构
