# repos/ 使用说明

这个目录专门放“收进来做事”的代码仓库。

## 默认规则

### 目录规则
- 每个项目一个目录
- 目录名尽量和仓库名一致
- 不要用 `test1`、`new-project`、`final-v2` 这种后期看不懂的名字

### 远端规则
对于 fork 型仓库，默认保持：
- `origin` = 老板自己的 fork
- `upstream` = 原始仓库

### 分支规则
默认不直接在 `main` 上改。

优先使用：
- `feature/<功能名>`
- `fix/<问题名>`
- `chore/<杂项名>`

例如：
- `feature/login-ui`
- `fix/build-error`
- `chore/setup-dev-env`

### 默认工作流
当老板说“复刻这个仓库/把这个项目收进来”时，默认执行：
1. fork 到老板 GitHub
2. clone 到 `repos/<项目名>`
3. 配好 `origin` 和 `upstream`
4. 验证 remotes

当老板说“开始改”时，默认执行：
1. 新建分支
2. 修改代码
3. 本地验证
4. commit
5. push 到 `origin`

### 常用命令
查看远端：
```bash
git remote -v
```

拉原仓库更新：
```bash
git fetch upstream
```

同步原仓库 main 到本地 main：
```bash
git checkout main
git merge upstream/main
```

推送到自己的仓库：
```bash
git push origin <branch>
```

## 当前已接入项目
- `claw-code` → `/home/ubuntu/.openclaw/workspace/repos/claw-code`

## 备注
以后新收进来的项目，默认都放到这个目录里，不再散落在 workspace 根目录。
