# AGENTS.md — Agent 操作入口

本文件只保留：项目定位、通用工作原则、关键安全边界、文档导航。**具体规约按需从 [`docs/agents/`](docs/agents/) 读取，不要一次性全部加载。**

## 项目定位

PowerShell 终端环境增强仓库（Windows 取向；Linux / WSL 部分能力未适配）：菜单式 tmux/SSH 会话管理、Spectre.Console 渲染、starship / fnm 集成。支持环境版本、目录职责与架构事实见 [`docs/agents/architecture.md`](docs/agents/architecture.md)，以该文件为准。

## 通用工作原则

- 改前先读相关源码，理解现有设计再动手。
- 优先最小改动：不做无关重构、不引入重依赖。
- 尊重现有公开命令、配置项与用户数据；不把用户偏好硬编码进仓库文件。
- 交付时说明改了哪些文件、实际做了哪些验证；**没跑过的测试不得声称通过**。

## 关键安全边界

- `Microsoft.PowerShell_profile.ps1` 只做模块加载与启动配置，不放业务逻辑。
- `Private/` 内部函数不得作为公开命令导出。
- **未经用户明确确认，不删除或销毁既有 tmux 会话。**
- 可能破坏用户数据或产生重大副作用的操作（删除文件、覆盖配置、影响共享环境等），先确认影响范围并取得授权。

## 文档导航（按需阅读）

| 你要做的事 | 读 |
|---|---|
| 了解目录职责 / 模块加载 / 菜单与配色不变量 | [`docs/agents/architecture.md`](docs/agents/architecture.md) |
| 新增或修改 PowerShell 函数（命名、作用域、错误处理、配置读取） | [`docs/agents/development.md`](docs/agents/development.md) |
| 改动 SSH 执行路径或 tmux 会话逻辑 | [`docs/agents/domain-ssh-tmux.md`](docs/agents/domain-ssh-tmux.md) |
| 提交前确认测试 / 静态分析 / 文档更新义务 / 测试基线 | [`docs/agents/testing.md`](docs/agents/testing.md) |
| 写 commit message 或 PR 标题 | [`docs/agents/commit-convention.md`](docs/agents/commit-convention.md) |
| 在本机执行 `pwsh` / 排查 pwsh 定位（机器专属记录） | [`docs/agents/environment.md`](docs/agents/environment.md) |
| 改菜单标题区天气 / `Weather.*` 配置 | [`docs/agents/wttr.md`](docs/agents/wttr.md) |
