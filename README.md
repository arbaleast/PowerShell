# ShellPrompt

快速、干净、可扩展的 PowerShell 终端增强体验。

[![MIT License](https://img.shields.io/badge/License-MIT-blue.svg)](ShellPrompt/LICENSE)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-blue.svg)](https://github.com/PowerShell/PowerShell)
[![Starship](https://img.shields.io/badge/Starship-Prompt-8356ff.svg)](https://starship.rs)
[![Tmux](https://img.shields.io/badge/Tmux-Sessions-1BB91F.svg)](https://github.com/tmux/tmux)

## ✨ 功能特点

### 远程开发体验

- **`Start-TmuxSession`** — 交互式菜单管理远程 tmux 会话。[`Start-TmuxSession.ps1`](ShellPrompt/Public/Start-TmuxSession.ps1)
- **`Copy-SshPublicKey`** — 一键推送 SSH 公钥到远程主机。[`Copy-SshPublicKey.ps1`](ShellPrompt/Public/Copy-SshPublicKey.ps1)
- **SSH Config 自动补全** — 自动解析 `~/.ssh/config` 主机列表，支持主机名 Tab 补全。[`Get-SshConfigHosts.ps1`](ShellPrompt/Private/Get-SshConfigHosts.ps1)

### 终端体验增强

- **ANSI 欢迎 Banner + 随机语录** — 启动时展示多彩 ASCII 横幅与随机语录。[`Show-UserScoopLogo.ps1`](ShellPrompt/Public/Show-UserScoopLogo.ps1)、[`quotes.txt`](data/quotes.txt)
- **PSReadLine 增强** — 基于历史记录的自动补全与优化导航体验。
- **Profile 加载计时** — 输出各阶段初始化耗时，便于调优。

### 交互式 UI 组件 (P2 阶段)

- **加载动画 (ProgressSpinner)** — 5 套 unicode 样式 (Braille / Ascii / Blocks / Dots / Arrows) 在耗时操作期间提供单行动态反馈；采用纯函数 + I/O 包装分层，PS 5.1 兼容（不依赖 `Start-ThreadJob`）。[`Show-ProgressSpinner.ps1`](ShellPrompt/Private/Show-ProgressSpinner.ps1)
- **`Invoke-WithProgress` 封装** — 接受 `-ScriptBlock` + 可选 `-PollScript`，内部 spin 循环 + 超时（默认 60s）+ 异常重拋，集成于 `Start-TmuxSession` 入口的 SSH 探测与远程会话刷新。([`Show-ProgressSpinner.ps1:209`](ShellPrompt/Private/Show-ProgressSpinner.ps1:209))
- **欢迎 Banner 纯函数** — `New-WelcomeBanner` 构造行数组，`Get-RandomQuote` 带 mtime 缓存避免反复读盘；`Start-TmuxSession` 入口处展示运行主题 banner（主机名+语录）。([`New-WelcomeBanner.ps1`](ShellPrompt/Private/New-WelcomeBanner.ps1))
- **输入提示 (InputPrompt)** — 支持默认值 / 校验器（bool / hashtable / throw 三种契约）/ Esc 取消 / Ctrl+U 清空，提取 `Update-InputBuffer` / `Test-InputValidation` 纯函数便于测试。([`Show-InputPrompt.ps1`](ShellPrompt/Private/Show-InputPrompt.ps1))
- **菜单状态机 (MenuMachine)** — P1 阶段实现的纯函数状态机驱动 `Show-HostSelector` 与 `Show-SessionManager`，统一处理键盘 / 过滤 / 焦点切换。([`Invoke-MenuMachine.ps1`](ShellPrompt/Private/Invoke-MenuMachine.ps1))
- **动态帮助面板** — 根据当前动作集合动态生成键位提示。([`New-DynamicHelpPanel.ps1`](ShellPrompt/Private/New-DynamicHelpPanel.ps1))
- **状态徽章** — Online / Attached / Detached / NetworkError / Pending / Disabled / Warning 七种状态点。([`New-StatusBadge.ps1`](ShellPrompt/Private/New-StatusBadge.ps1))

### 现代工具链集成

- **Starship Prompt 延迟加载** — 跨 Shell 提示符，显示 git 上下文、Node 版本等信息，推迟到首次交互前加载。
- **Fnm (Node.js) 自动切换** — 进入项目目录时自动切换对应 Node 版本。

### 工作流便利

- **`Invoke-Reload`** — 一键重载 PowerShell Profile。[`Invoke-Reload.ps1`](ShellPrompt/Public/Invoke-Reload.ps1)
- **全局别名** — `ll` (Get-ChildItem)、`which` (where.exe)、`sss` (Start-TmuxSession)、`ssh-copy-id` (Copy-SshPublicKey)。

## 🚀 安装

### 前置依赖

| 依赖 | 说明 |
|------|------|
| PowerShell 7+ | **推荐**，Windows PowerShell 5.1 作为兜底 |
| starship | 可选 — 现代化 Prompt，通过 `Get-Command starship` 检测 |
| fnm | 可选 — Node.js 版本管理，通过 `Get-Command fnm` 检测 |
| ssh | 可选 — 远程连接时按需使用 |
| tmux | 可选 — 远程会话管理时按需使用 |

> **注意**：本模块**未发布到 PSGallery**，请使用本地路径导入。

### 安装步骤

1. **克隆仓库**

   ```powershell
   git clone https://github.com/arbaleast/PowerShell.git "$HOME\Documents\PowerShell"
   ```

2. **激活 Profile**

   复制或创建链接将 [`Microsoft.PowerShell_profile.ps1`](Microsoft.PowerShell_profile.ps1) 指向 PowerShell `$PROFILE` 路径：

   ```powershell
   # 将仓库中的 profile 复制到 $PROFILE 路径
   Copy-Item "$HOME\Documents\PowerShell\Microsoft.PowerShell_profile.ps1" $PROFILE
   ```

3. **首次启动**

   启动新的 PowerShell 窗口，ShellPrompt 将自动通过延迟加载机制初始化。首次调用 `sss` 或 `ssh-copy-id` 时触发模块导入。

### 手动调试

如需手动验证模块加载：

```powershell
Import-Module ./ShellPrompt/ShellPrompt.psd1
```

### 平台注意事项

| 平台 | 注意事项 |
|------|----------|
| **Windows** | 建议使用 `code $PROFILE` 配对编辑器路径 |
| **Linux / WSL** | 注意 `ssh-agent` 转发配置；SSH ControlMaster socket 路径与 Windows 存在差异 |

## 🎨 配置

### 配置文件位置

```powershell
$HOME/.ShellPrompt/config.ps1
```

### 配置优先级

**用户配置 → 默认配置**。用户自定义项覆盖模块内置默认值，见 [`Initialize-Config.ps1`](ShellPrompt/Private/Initialize-Config.ps1)。

### 完整配置项

#### Paths 域

| 键 | 类型 | 默认值 | 说明 |
|----|------|--------|------|
| `Quotes` | string | `{moduleRoot}/data/quotes.txt` | 随机语录文件路径 |
| `LogPath` | string | `$env:TEMP/ShellPrompt/shellprompt.log` | 日志输出路径 |

#### Colors 域（ANSI 转义码）

| 键 | 默认值 | 说明 |
|----|--------|------|
| `FreshGreen` | `\e[38;2;137;209;133m` | 主色调（亮绿） |
| `SageGreen` | `\e[38;2;159;177;159m` | 辅助绿 |
| `DarkGray` | `\e[38;2;50;50;50m` | 深灰 |
| `MidGray` | `\e[38;2;100;100;100m` | 中灰 |
| `LightGray` | `\e[38;2;180;180;180m` | 浅灰 |
| `White` | `\e[38;2;255;255;255m` | 白色 |
| `Rst` | `\e[0m` | 重置样式 |
| `Bold` | `\e[1m` | 加粗 |
| `Dim` | `\e[2m` | 变暗 |

#### Keys 域（虚拟键码）

| 键 | 默认值 | 说明 |
|----|--------|------|
| `Up` | `38` | 上方向键 |
| `Down` | `40` | 下方向键 |
| `Enter` | `13` | 回车键 |
| `Esc` | `27` | 退出键 |

#### SSH 域

| 键 | 类型 | 默认值 | 说明 |
|----|------|--------|------|
| `ConnectTimeout` | int | `5` | SSH 连接超时（秒） |
| `ForceTTy` | bool | `$true` | 强制分配 PTY |
| `LastHost` | string | `$null` | 上次使用的主机，在会话管理器中优先显示 |

### 用户配置示例

```powershell
# ~/.ShellPrompt/config.ps1
$Config.Colors.FreshGreen = "\e[38;2;0;255;0m"  # 覆盖主色调为亮绿色
$Config.SSH.ConnectTimeout = 10                  # 连接超时延长至 10 秒
```

> **提示**：通过 `Get-CachedConfig` 统一访问配置值。运行时修改配置后，需清除 `$script:ColorCache` 缓存才能生效，或执行 `Invoke-Reload` 重载。

## ⚡ 命令一览

| 命令 | 说明 | 关键参数 | 依赖 | 源文件 |
|------|------|----------|------|--------|
| `Show-UserScoopLogo` | 显示 ANSI 欢迎 Banner 及随机语录(委托 `New-WelcomeBanner` + `Get-RandomQuote`,带 mtime 缓存) | `-QuotesPath`、`-ColorPrimary` | — | [`Show-UserScoopLogo.ps1`](ShellPrompt/Public/Show-UserScoopLogo.ps1) |
| `Start-TmuxSession` | 远程 tmux 会话交互式管理(进入后展示欢迎 banner + SSH 探测 / 会话刷新期间 spin 动画 + 超时控制) | `-HostName` | ssh、tmux | [`Start-TmuxSession.ps1`](ShellPrompt/Public/Start-TmuxSession.ps1) |
| `Copy-SshPublicKey` | 一键推送 SSH 公钥到远程主机 | `-RemoteHost`、`-IdentityFile`、`-Port` | ssh | [`Copy-SshPublicKey.ps1`](ShellPrompt/Public/Copy-SshPublicKey.ps1) |
| `Invoke-Reload` | 一键重载 PowerShell 配置 | — | — | [`Invoke-Reload.ps1`](ShellPrompt/Public/Invoke-Reload.ps1) |
| `Invoke-WithProgress` | **P2 内部封装**:spin 动画期间执行 `-ScriptBlock`,支持 `-PollScript` 完成检测与 `-TimeoutSeconds`,异常统一重拋 | `-ScriptBlock`、`-PollScript`、`-TimeoutSeconds`、`-Style` | — | [`Show-ProgressSpinner.ps1:209`](ShellPrompt/Private/Show-ProgressSpinner.ps1:209) |

> **P2 UX 流程**(`Start-TmuxSession` 启动后顺序):
> 1. **欢迎 banner** — `New-WelcomeBanner` 渲染主机名 + 随机语录(见 [`New-WelcomeBanner.ps1`](ShellPrompt/Private/New-WelcomeBanner.ps1))
> 2. **SSH 探测 + 会话刷新** — `Invoke-WithProgress` 包覆,期间单行 Braille spinner 滚动;超时默认 60s(见 [`Show-ProgressSpinner.ps1`](ShellPrompt/Private/Show-ProgressSpinner.ps1))
> 3. **主机 / 会话选择** — `Show-HostSelector` / `Show-SessionManager` 由 `Invoke-MenuMachine` 状态机驱动(见 [`Invoke-MenuMachine.ps1`](ShellPrompt/Private/Invoke-MenuMachine.ps1))
> 4. **连接 / 附着** — `Connect-TmuxSession` / `New-TmuxSession` / `Remove-TmuxSession` 分派,期间 `Save-OriginalTerminalState` + `Reset-TerminalMode` 在 `try/finally` 中保护终端态

### 别名

| 别名 | 映射命令 |
|------|----------|
| `ll` | `Get-ChildItem` |
| `which` | `where.exe` |
| `sss` | `Start-TmuxSession` |
| `ssh-copy-id` | `Copy-SshPublicKey` |

> 别名由 `Microsoft.PowerShell_profile.ps1` 以 `-Scope Global` 注册，模块内不再定义。

### 🛠️ 开发模式重载

改完 `ShellPrompt/Private/*.ps1` / `Public/*.ps1` / `ShellPrompt.psm1` / `~/.ShellPrompt/config.ps1` 后,**不需要重启 PowerShell**,跑一次:

```powershell
Invoke-Reload          # 默认: 重载 PROFILE + ShellPrompt, 打印 " [OK] ..." 提示
Invoke-Reload -Quiet   # 静默模式(脚本/管道场景用)
```

原理: 卸载 `ShellPrompt` 模块 + dot-source `$PROFILE`,后者中的 `Ensure-ShellPrompt` 会重新 `Import-Module` 拉起最新代码(见 [`Microsoft.PowerShell_profile.ps1`](Microsoft.PowerShell_profile.ps1:25))。

> **为什么不做 FileSystemWatcher 自动重载?**
> 一次性 ~150 行代码 + EventManager + ThreadPool + 跨 runspace SessionState 读写,
> 远超本项目"小而深"模块边界;且 Pester 虚高 + PS 5.1 scope 链路过深,
> 实测 7 次重试仍无法稳定 fire。手动 `Invoke-Reload` 成本低、可预测。
>
> **推荐编辑器工作流**: VSCode / vim 配 `chokidar` / `watchexec` 监听 `ShellPrompt/*.ps*`,
> 存盘后自动调 `Invoke-Reload -Quiet`(项目根 `.vscode/settings.json` 或 `~/.config/watchexec/config.toml`)。

## 🏗️ 架构

### 目录结构

```
PowerShell/
├── Microsoft.PowerShell_profile.ps1   # 入口：仅处理模块加载与启动配置
├── AGENTS.md                          # AI 代理开发约束
├── README.md
├── data/
│   └── quotes.txt                     # 随机语录数据
└── ShellPrompt/                       # 模块根目录
    ├── ShellPrompt.psd1               # 模块清单 (ModuleVersion 1.3.0)
    ├── ShellPrompt.psm1               # 模块入口脚本
    ├── Settings.ScriptAnalyzer.psd1   # PSScriptAnalyzer 规则配置
    ├── CHANGELOG.md
    ├── LICENSE                        # MIT 协议
    ├── Tests/                         # Pester 测试套件
    │   └── ShellPrompt.Tests.ps1      # 17 项测试
    ├── Public/                        # 用户面向命令（稳定 API）
    │   ├── Copy-SshPublicKey.ps1
    │   ├── Invoke-Reload.ps1
    │   ├── Show-UserScoopLogo.ps1
    │   └── Start-TmuxSession.ps1
    └── Private/                       # 内部辅助函数（不暴露给用户）
        ├── Connect-TmuxSession.ps1        # 附着已有 tmux 会话
        ├── ConvertTo-SshEscapedString.ps1 # SSH 单引号转义
        ├── Get-KeyboardFilter.ps1         # [P1] PSReadLine 键盘事件过滤
        ├── Get-SshArgs.ps1                # SSH 参数生成器
        ├── Get-SshConfigHosts.ps1         # SSH config 主机解析
        ├── Get-SshSocketPath.ps1          # SSH socket 路径
        ├── Get-TmuxSessions.ps1           # 远程 tmux 探测与列表
        ├── Initialize-Config.ps1          # 配置初始化与缓存
        ├── Invoke-ConsoleMenu.ps1         # 终端交互式菜单 UI
        ├── Invoke-MenuMachine.ps1         # [P1] 菜单状态机（驱动 HostSelector/SessionManager）
        ├── Invoke-SshCaptureOutput.ps1    # SSH 异步输出捕获
        ├── Invoke-SshCommand.ps1          # SSH 命令调度（主线逻辑）
        ├── New-DynamicHelpPanel.ps1       # [P1] 动态生成键位提示
        ├── New-StatusBadge.ps1            # [P1] 状态徽章（Online/Attached/Detached/...）
        ├── New-TmuxSession.ps1            # 创建新 tmux 会话
        ├── New-WelcomeBanner.ps1          # [P2] 欢迎 Banner 纯函数（主机名+随机语录）
        ├── Remove-TmuxSession.ps1         # 删除 tmux 会话
        ├── Reset-TerminalMode.ps1         # 终端编码/TERM 恢复
        ├── Save-OriginalTerminalState.ps1 # 终端状态保存
        ├── Show-InputPrompt.ps1           # [P2] 输入提示（默认值/校验器/Esc 取消/Ctrl+U 清空）
        ├── Show-ProgressSpinner.ps1       # [P2] 加载动画 + Invoke-WithProgress 封装
        ├── Start-SshInteractive.ps1       # 交互式 SSH 启动
        └── Test-SshHostName.ps1           # 主机名校验
```

### 加载流程

```
PowerShell 启动
     │
     ▼
┌─────────────────────────────────────────────┐
│ ① dot-source $PROFILE                      │
│   → Microsoft.PowerShell_profile.ps1        │
└─────────────────────────────────────────────┘
     │
     ▼
┌─────────────────────────────────────────────┐
│ ② Profile Phase 1                          │
│   · dot-source 顺序（修复 P2-2 依赖链）:    │
│     ① Initialize-Config.ps1                 │
│     ② New-WelcomeBanner.ps1                 │
│     ③ Show-UserScoopLogo.ps1                │
│   · 显示欢迎 Banner (委托 New-WelcomeBanner │
│     + Get-RandomQuote,带 mtime 缓存)        │
│   · 设置 ll / which 别名                    │
└─────────────────────────────────────────────┘
     │
     ▼
┌─────────────────────────────────────────────┐
│ ③ Profile Phase 2 (延迟初始化)              │
│   · Starship Prompt                         │
│   · Fnm (Node.js)                           │
│   · PSReadLine                              │
└─────────────────────────────────────────────┘
     │
     ▼
┌─────────────────────────────────────────────┐
│ ④ Profile Phase 3                          │
│   · 包装 prompt 函数                        │
└─────────────────────────────────────────────┘
     │
     ▼
┌─────────────────────────────────────────────┐
│ ⑤ 首次调用命令                              │
│   Ensure-ShellPrompt →                      │
│   Import-Module ShellPrompt.psd1            │
└─────────────────────────────────────────────┘
     │
     ▼
┌─────────────────────────────────────────────┐
│ ⑥ 模块加载                                 │
│   · dot-source Public/*.ps1                 │
│   · dot-source Private/*.ps1                │
│   · 加载 ~/.ShellPrompt/config.ps1          │
└─────────────────────────────────────────────┘
```

### 关注点分离

- [`Microsoft.PowerShell_profile.ps1`](Microsoft.PowerShell_profile.ps1) — **仅处理**模块加载、环境初始化与启动配置。**不得包含**复杂业务逻辑。
- [`Public/`](ShellPrompt/Public/) — 用户面向命令，保持稳定 API 行为，包含 `.SYNOPSIS` 等帮助注释。
- [`Private/`](ShellPrompt/Private/) — 内部辅助函数，**不得暴露**给用户。

## 🛠️ 开发者指南

以下约束引自 [`AGENTS.md`](AGENTS.md)，所有贡献者必须遵守。

### 命名与作用域

> - **ALWAYS** use approved PowerShell verbs (`Get-Verb`). (e.g., `Get-TmuxSession`, `Connect-SshHost`). **NEVER** use unapproved verbs like `test1` or `ssh123`.
> - **NEVER** use global variables (`$global:`) without explicit architectural justification. **ALWAYS** prefer `$script:` or local scope.

### 函数分解与单一职责

> - **PREFER** small, focused functions over monolithic ones. When a function exceeds ~80 lines or handles multiple concerns, split it:
>   - `Invoke-SshCommand` → `Get-SshArgs` (arg building) + `Invoke-SshCaptureOutput` (capture I/O) + backbone (dispatch logic)
>   - `Start-TmuxSession` → `Connect-TmuxSession` / `New-TmuxSession` / `Remove-TmuxSession`
> - **Shared utilities**: Extract reusable logic into `Private/` utility functions (e.g., `ConvertTo-SshEscapedString`, `Test-SshHostName`, `Save-OriginalTerminalState`).
> - **Terminal state pattern**: Use `Save-OriginalTerminalState` + `Reset-TerminalMode` in `try {} finally {}` for any SSH command that changes terminal encoding/TERM.

### 输出注解

> - **ALWAYS** add `[OutputType()]` annotation to every function. Use exact types: `[void]`, `[string]`, `[bool]`, `[object]`, `[PSCustomObject]`, `[hashtable]`, `[string[]]`.
> - **ALWAYS** add `[CmdletBinding()]` to every advanced function.

### 错误处理约定

> | 场景 | 方式 | 示例 |
> |------|------|------|
> | 参数校验 | `[ValidateScript()]` + `throw` | 非法主机名字符 |
> | 运行时致命错误 | `throw` (终止性) | 配置缺失、依赖不可用 |
> | 可恢复失败 | `Write-Warning` (非终止性) | SSH 超时、tmux 不可用 |
> | 外部命令缺失 | `Get-Command` 检查 → `Write-Warning` | tmux、ssh 未安装 |
> | **例外**: UI 渲染 | `Write-Host` 允许 | `Invoke-ConsoleMenu`、`Show-UserScoopLogo` |

### 配置

> - **NEVER** hard-code user preferences (e.g., Bad: `$Theme="starship"` | Good: `$config.Theme`).
> - Follow Configuration Priority: `User configuration -> Default configuration`.
> - User-specific settings MUST NOT be stored inside repository files.

### 外部依赖

> Before calling external commands, you **MUST**:
> 1. Check if the command exists (`Get-Command`).
> 2. Provide clear error messages if missing.
> 3. **NEVER** silently fail.

### SSH 与 tmux 红线

> - **SSH**: Changes MUST consider path/execution differences between Windows OpenSSH, Linux OpenSSH, and WSL.
> - **tmux**: Changes MUST respect existing sessions, session naming, and reconnect behaviors. **CRITICAL: NEVER delete or destroy existing tmux sessions without explicit user confirmation.**

### 测试

> - **Testing**: Before submitting changes, verify module loading (`Import-Module ./ShellPrompt`). Run tests via `Invoke-Pester` (Assume Pester v5 syntax). Run PSScriptAnalyzer via `Invoke-ScriptAnalyzer -Settings ./ShellPrompt/Settings.ScriptAnalyzer.psd1`. Any changes involving profile loading, SSH, or tmux MUST be flagged for manual testing.

### 提交规范

> ALWAYS use Conventional Commits: `type(scope): message`
> - **Types**: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`
> - *Example*: `feat(tmux): add session rename support`

## 🔧 故障排除

| 症状 | 可能原因 | 解决方案 |
|------|----------|----------|
| 模块导入失败 | Profile 路径不正确或 `ShellPrompt.psd1` 未找到 | 确认 `$PROFILE` 指向正确路径；检查 [`ShellPrompt.psd1`](ShellPrompt/ShellPrompt.psd1) 是否存在 |
| Profile 启动报 `Get-RandomQuote` / `New-WelcomeBanner` 未识别 | `Microsoft.PowerShell_profile.ps1` Phase 1 dot-source 链缺失 `New-WelcomeBanner.ps1`（P2-2 重构 `Show-UserScoopLogo` 后新增的依赖） | 在 `Show-UserScoopLogo.ps1` 之前显式 dot-source [`New-WelcomeBanner.ps1`](ShellPrompt/Private/New-WelcomeBanner.ps1) |
| 显示 "ShellPrompt 模块未正确导入" | 模块未在启动流程中加载 | 手动执行 `Import-Module ./ShellPrompt/ShellPrompt.psd1` 验证 |
| `Start-TmuxSession` 提示 "SSH 配置中未找到任何主机" | `~/.ssh/config` 文件缺失或为空 | 编辑 `~/.ssh/config` 添加主机配置 |
| 远程主机无 tmux | 远程未安装 tmux | 输出黄色警告并自动降级为直连 SSH |
| 主机名包含非法字符 | 输入含 shell 特殊字符 | 主机名仅允许字母数字、`.`、`-`、`_` |
| `Copy-SshPublicKey` 提示 "未找到任何默认公钥" | 本地未生成 SSH 密钥对 | 执行 `ssh-keygen -t ed25519` 生成密钥 |
| Starship / Fnm 静默失败 | 外部命令未安装或不在 PATH 中 | 使用 `Get-Command starship` 和 `Get-Command fnm` 验证安装 |
| PSReadLine 不可用 | 未安装 PSReadLine 模块 | 执行 `Install-Module PSReadLine -Force` |
| 网络错误 | SSH 连接超时或网络不可达 | 标记为 `NetworkError` 跳过缓存，重试或检查网络连通性 |
| tmux 删除会话 | 误操作 | 删除会话**必须**通过交互式菜单显式选择目标会话 |

## 📜 协议

本项目基于 MIT 协议开源，详见 [`LICENSE`](ShellPrompt/LICENSE)。
