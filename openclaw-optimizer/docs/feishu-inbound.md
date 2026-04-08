# Feishu 入站需求桥接

目标：作为备用通道，在需要公网 HTTP 回调时将飞书消息落地为 OpenClaw 任务。

默认策略：优先使用 Feishu websocket + `/newtask` 指令派发（见 `docs/feishu-command-skill.md`）。

## 1) 配置

编辑：`config/inbound-feishu.json`

- `enabled`: 默认 `false`，只有需要 HTTP 回调时再开启
- `authToken`: 建议设置随机字符串
- `defaultProjectId`: 任务默认归属项目
- `autoStart`: `true` 则自动执行 `start-task.sh`

## 2) 启动

```bash
./scripts/feishu-inbound.sh start
./scripts/feishu-inbound.sh status
```

## 3) 飞书回调地址

```
http://<host>:8787/feishu/webhook?token=<authToken>
```

## 4) 消息格式

纯文本，支持可选字段：

```text
title: 做官网一期
project: internal-openclaw
type: frontend-feature
priority: high
实现一个公司官网，含首页、产品页、联系页；要求可部署、含基础测试。
```

说明：
- 未提供 `project/type/priority` 时使用配置默认值。
- 第一行默认作为 `title`（若未显式 `title:`）。

## 5) 落地效果

- 任务 JSON：`runtime/tasks/active/<task_id>.json`
- 入站事件：`runtime/events/feishu-inbound-events-YYYYMMDD.jsonl`
- 服务日志：`runtime/logs/feishu-inbound-YYYYMMDD.log`

## 6) 停止

```bash
./scripts/feishu-inbound.sh stop
```
