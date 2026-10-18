# AGENTS.md — AI Agent 约束（根路由）

本文件是本仓库 agent 约束的唯一入口：只保留身份、命令、红线与架构速查，细节按下表路由到 `docs/agents/` 下的子文件。

## 🎯 Project Identity

- 仓库目标：PowerShell 终端环境增强，提供**快速、干净、可扩展**的 PowerShell 体验，并保持跨环境兼容。
- 支持环境：PowerShell **7.6+**（唯一支持版本；`ShellPrompt.psd1` 声明 `PowerShellVersion = '7.6'`，抬到 7.6 的原因是菜单主轨依赖的 `Modules/PSTui` 为 .NET 10 二进制模块，要求 PS 7.6+）、Windows、Linux、WSL。
- **不再支持 Windows PowerShell 5.1**。
- UI 层已单轨化 Spectre.Console，硬依赖 `Modules/PwshSpectreConsole`，缺失即模块加载抛终止错误。
- 核心集成：`ShellPrompt` 模块、`ssh` helper 命令、`tmux` 会话管理、`starship`、`fnm`（Node.js）。

## ⚡ 权威命令

```powershell
# 模块加载冒烟：提交前确认模块可正常导入
Import-Module ./ShellPrompt

# 测试：Pester v5 语法
Invoke-Pester ./ShellPrompt/Tests -Output Detailed

# 静态分析：使用仓库自带的 PSScriptAnalyzer 配置（-Path 为必填参数）
Invoke-ScriptAnalyzer -Path ./ShellPrompt -Recurse -Settings ./ShellPrompt/Settings.ScriptAnalyzer.psd1

# 文档同步核对：确认用户可见变更已写入 README.md（可用 git diff --name-only 辅助判断）
```

涉及 profile 加载、SSH、tmux 的改动必须标记人工测试。

## 🚧 三层边界

### Always do

- 改前先读相关文件，理解现有设计后再动手。
- 保持变更最小：不做无关重构、不引入重依赖。
- 交付时说明改了什么文件、测试结果如何。

### Ask first

- 未经用户确认，不破坏现有命令行为。
- 大型架构变更先征得许可再实施。
- 删除或销毁既有 tmux 会话前必须取得用户明确确认。

### Never do

- **CRITICAL: NEVER 删除或销毁既有 tmux 会话**，除非用户明确确认。
- **NEVER** 把复杂业务逻辑写进 `Microsoft.PowerShell_profile.ps1`（profile 只做模块加载、环境初始化、启动配置）。
- **NEVER** 把 `Private/` 内部函数暴露给用户。
- **NEVER** 在仓库文件里硬编码用户偏好（用 `$config.*`，优先级：用户配置 → 默认配置）。
- **NEVER** 静默失败：调用外部命令前先 `Get-Command` 检查，缺依赖时给出清晰错误。
- **NEVER** 未经说明就修改 `Public/` 既有命令的行为。

## 🗺️ 路由表

| 任务场景 | 加载文件 | 何时读 |
|---|---|---|
| 架构与目录职责、双轨菜单与降级 | `docs/agents/architecture.md` | 你要往哪个目录放文件、改动会碰到模块加载/兼容降级路径，或要动 `Microsoft.PowerShell_profile.ps1`、`Public/`、`Private/`、`Settings.ScriptAnalyzer.psd1` 的职责边界时 |
| 命名、作用域、函数拆分、输出注解、错误处理、配置、外部依赖 | `docs/agents/development.md` | 你准备新增或修改任何 PowerShell 函数（命名、变量作用域、`[OutputType()]`/`[CmdletBinding()]`、异常与 `Write-Warning` 的选择、配置读取、调用 `git`/`ssh`/`tmux`/`starship`/`fnm` 等外部命令）时 |
| SSH 跨平台差异、tmux 会话与红线 | `docs/agents/domain-ssh-tmux.md` | 你的改动涉及 SSH 执行路径（Windows/Linux/WSL 路径与执行差异）或 tmux 会话创建、命名、重连、销毁时 |
| 测试命令、静态分析、README 文档义务 | `docs/agents/testing.md` | 你要提交改动前确认该跑哪些测试、该跑什么静态分析、用户可见行为变化后如何补 `README.md` 时 |
| 提交信息格式与 type 枚举 | `docs/agents/commit-convention.md` | 你要写 commit message 或 PR 标题时 |

## 📌 核心架构速查

- profile 只做加载与启动配置，业务逻辑留在 `ShellPrompt/` 模块内。
- 交互菜单双轨：`Get-ConsoleUiBackend` 在模块加载期判定 `GridView` 主轨 / `AnsiFallback` 降级轨，调用方不感知后端差异。
- `PwshSpectreConsole` 是硬依赖：加载失败时 `ShellPrompt.psm1` 直接 `throw`，不做静默降级。
- `Public/` 面向用户，`Private/` 内部私有；`Settings.ScriptAnalyzer.psd1` 与代码约定保持同步。
