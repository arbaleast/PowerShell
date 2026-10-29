# AGENTS.md — AI Agent 约束（根路由）

本文件是本仓库 agent 约束的唯一入口：只保留身份、命令、红线与架构速查；命名 / 作用域 / 函数拆分 / 输出注解 / 错误处理 / 配置 / 外部依赖 → [`docs/agents/development.md`](docs/agents/development.md);SSH 跨平台 / tmux 红线 → [`docs/agents/domain-ssh-tmux.md`](docs/agents/domain-ssh-tmux.md);测试 / 静态分析 / README / CHANGELOG 义务 → [`docs/agents/testing.md`](docs/agents/testing.md);提交信息格式 → [`docs/agents/commit-convention.md`](docs/agents/commit-convention.md)。

## 🎯 Project Identity

- 仓库目标：PowerShell 终端环境增强，提供**快速、干净、可扩展**的 PowerShell 体验，并保持跨环境兼容。
- 支持环境：PowerShell **7.6+**（唯一支持版本；`ShellPrompt.psd1` 声明 `PowerShellVersion = '7.6'`，抬到 7.6 的原因是菜单主轨依赖的 `Modules/PSTui` 为 .NET 10 二进制模块，要求 PS 7.6+）、Windows、Linux、WSL。
- **不再支持 Windows PowerShell 5.1**。
- UI 层已单轨化 Spectre.Console，硬依赖 `Modules/PwshSpectreConsole`，缺失即模块加载抛终止错误。
- 控制台交互菜单也已单轨化：只保留 PSTui `Out-ConsoleGridView`（GridView）主轨，自研 ANSI 降级轨（AnsiFallback）已于 2026-10-18 整体移除。
- 核心集成：`ShellPrompt` 模块（Public **5** 个、Private **37** 个）、`ssh` helper 命令、`tmux` 会话管理、`starship`、`fnm`（Node.js）。
- 启动期性能契约细节：见 [`docs/agents/architecture.md`](docs/agents/architecture.md) 「启动期时序」。

## ⚡ 权威命令

```powershell
# 模块加载冒烟：提交前确认模块可正常导入
Import-Module ./ShellPrompt

# 测试：Pester v5 语法
Invoke-Pester ./ShellPrompt/Tests -Output Detailed

# 静态分析：使用仓库自带的 PSScriptAnalyzer 配置（-Path 为必填参数）
Invoke-ScriptAnalyzer -Path ./ShellPrompt -Recurse -Settings ./ShellPrompt/Settings.ScriptAnalyzer.psd1

# 文档同步核对：用户可见变更必须同步 README + CHANGELOG（详见「📜 文档同步义务」段）
git diff --name-only README.md ShellPrompt/CHANGELOG.md
```

**人工测试标记规则**：涉及 **profile 加载 / SSH / tmux / prompt 渲染** 的改动，必须在 PR 描述中标注 `[人工测试必做]`（现阶段不进 CHANGELOG）；最小真机验证集见 [`docs/agents/testing.md`](docs/agents/testing.md) 「人工测试标记」段。

**临时输出约束**：`Invoke-Pester` / `Invoke-ScriptAnalyzer` / 任何调试探针输出必须落到 `.agent_cache/`（已 `.gitignore`），**禁止**在仓库根或 `ShellPrompt/` 下散落 `pester.txt` / `pssa.txt` / `*.tmp` 等残留文件。

## 📍 pwsh 安装位置

- **可执行文件绝对路径**：`D:\Env\UserScoop\apps\pwsh\current\pwsh.exe`（`current` 为指向版本目录 `D:\Env\UserScoop\apps\pwsh\7.6.3\pwsh.exe` 的 Scoop 链接，升级后真实版本目录会变，`current` 路径保持不变）。
- **已安装版本**：PowerShell 7.6.3（`pwsh --version` 输出 `PowerShell 7.6.3`）。
- **安装方式**：Scoop 安装（自定义 Scoop 根目录 `D:\Env\UserScoop`，非默认的 `%USERPROFILE%\scoop`）。
- **PATH 状态**：`D:\Env\UserScoop\shims` 已在用户 PATH 中，但**未生成 `pwsh` shim**，因此 `where pwsh` 与 `Get-Command pwsh` 均无结果；请直接使用上面的绝对路径，不要用全盘扫描（`where /r C:\ pwsh.exe`）定位。
- **WindowsApps 别名**：不存在（`%LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe` 不存在），无 0 字节 app execution alias 误用风险。

常用查询命令：

```powershell
# PowerShell 内部查询（若已加入 PATH 时有效）
Get-Command pwsh | Select-Object -ExpandProperty Source

# cmd 内部查询（若已加入 PATH 时有效）
where pwsh

# 兜底：直接按本仓库记录的位置查询
Get-Item 'D:\Env\UserScoop\apps\pwsh\current\pwsh.exe' | Select-Object -ExpandProperty FullName
```

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

## 🌤️ wttr 项目级约束

PSTui 菜单标题区天气走 [`Get-WttrTitleSuffix`](ShellPrompt/Private/Get-WttrTitleSuffix.ps1)（[`ShellPrompt/Private/Get-WttrTitleSuffix.ps1`](ShellPrompt/Private/Get-WttrTitleSuffix.ps1)），基于 [`Get-WttrWeatherDescMap`](ShellPrompt/Private/Get-WttrWeatherDescMap.ps1)（[`ShellPrompt/Private/Get-WttrWeatherDescMap.ps1`](ShellPrompt/Private/Get-WttrWeatherDescMap.ps1)）的中文翻译映射，渲染入口在 `Private/Invoke-GridViewMenu.ps1` 的三个 `Invoke-GridView*` 调用点。

**配置域**：`$config.Weather.*`
- `Weather.Enabled` — 总开关（默认 `$true`）。
- `Weather.ExtraWeatherDescMap` — 用户扩展映射（`[ordered]@{}` 形式），合并到内置字典之上。

**一函数一文件**：`Get-WttrTitleSuffix.ps1` / `Get-WttrWeatherDescMap.ps1` 是拆分后的最小单元，dot-source 后模块作用域可见；`Invoke-GridViewMenu.ps1` 不再内联这些函数。

**端点与缓存**：标题区走 [`Get-WttrWeather`](ShellPrompt/Private/Get-WttrWeather.ps1)（[`ShellPrompt/Private/Get-WttrWeather.ps1`](ShellPrompt/Private/Get-WttrWeather.ps1)）的自拼端点 `https://wttr.in/?format=j1&lang=zh`，与公开命令 [`Update-Weather`](ShellPrompt/Public/Update-Weather.ps1)（`?format=3` 短格式）**不共享缓存**（缓存键 `CustomUrl|...` vs `Short|...`）。

**重做原则**：wttr 相关修改同时改 `Get-WttrTitleSuffix.ps1` / `Get-WttrWeatherDescMap.ps1` / `Invoke-GridViewMenu.ps1`，避免再次内联到分发器。

## 📜 文档同步义务

**用户可见行为变化**（Public 函数签名 / 配置键 / 默认值 / 菜单交互 / 渲染入口 / 模块加载顺序）必须**同时**同步：

- [`README.md`](README.md)（用户文档；新增 / 修改 / 弃用命令必须给最小可运行示例）。
- [`ShellPrompt/CHANGELOG.md`](ShellPrompt/CHANGELOG.md)（`[Unreleased]` 段 `### Added` / `### Changed` / `### Fixed` / `### Removed`）；**注意**：用户已决定 CHANGELOG 历史永久丢失，当前 134 行；阶段 B 后新增条目**仍不进 CHANGELOG**，同步义务落到 PR 描述与 `README.md`。

**Pester 基线**：`266 Pass / 0 Fail`（阶段 C 实测；阶段 B 实测基线 264，新增 2 个 wttr 测试文件）。任何阶段后，修改都不得让 Pass 数回退或引入 Fail；测试命令与基线刷新触发条件见 [`docs/agents/testing.md`](docs/agents/testing.md)。

**临时输出约束**：所有 `Invoke-Pester` / `Invoke-ScriptAnalyzer` / wttr 探针输出必须落到 `.agent_cache/`（已 `.gitignore`），**禁止**仓库根临时文件。

## 🗺️ 路由表

| 任务场景 | 加载文件 | 何时读 |
|---|---|---|
| 架构与目录职责、单轨菜单与依赖前提、启动图缓存、启动期时序、PSTui 标题区天气 | [`docs/agents/architecture.md`](docs/agents/architecture.md) | 你要往哪个目录放文件、改动会碰到模块加载/依赖检测路径，或要动 `Microsoft.PowerShell_profile.ps1`、`Public/`、`Private/`、`Settings.ScriptAnalyzer.psd1` 的职责边界时；或准备改动 `Weather.Enabled` / `ExtraWeatherDescMap` / wttr 缓存键时 |
| 命名、作用域、函数拆分、输出注解、错误处理、配置、外部依赖 | [`docs/agents/development.md`](docs/agents/development.md) | 你准备新增或修改任何 PowerShell 函数（命名、变量作用域、`[OutputType()]`/`[CmdletBinding()]`、异常与 `Write-Warning` 的选择、配置读取、调用 `git`/`ssh`/`tmux`/`starship`/`fnm` 等外部命令）时 |
| SSH 跨平台差异、tmux 会话与红线 | [`docs/agents/domain-ssh-tmux.md`](docs/agents/domain-ssh-tmux.md) | 你的改动涉及 SSH 执行路径（Windows/Linux/WSL 路径与执行差异）或 tmux 会话创建、命名、重连、销毁时 |
| 测试命令、静态分析、README / CHANGELOG 文档义务、人工测试标记、回跑基线触发条件 | [`docs/agents/testing.md`](docs/agents/testing.md) | 你要提交改动前确认该跑哪些测试、该跑什么静态分析、用户可见行为变化后如何补 `README.md`，以及哪些改动会强制回跑 Pester / PSScriptAnalyzer 基线时 |
| 提交信息格式与 type 枚举 | [`docs/agents/commit-convention.md`](docs/agents/commit-convention.md) | 你要写 commit message 或 PR 标题时 |

## 📌 核心架构速查

- profile 只做加载与启动配置，业务逻辑留在 `ShellPrompt/` 模块内。
- 交互菜单单轨：只保留 `GridView` 主轨（`Modules/PSTui` 的 `Out-ConsoleGridView`）；主轨不可用由 `Assert-ConsoleUiReady` 抛出可定位终止错误，**不再静默降级**。
- `PwshSpectreConsole` 是硬依赖：加载失败时 `ShellPrompt.psm1` 直接 `throw`。
- `Public/` 面向用户，`Private/` 内部私有；`Settings.ScriptAnalyzer.psd1` 与代码约定保持同步。
- 完整描述：见 [`docs/agents/architecture.md`](docs/agents/architecture.md) 「目录职责」与「兼容性与降级」。
