# ShellPrompt

快速、干净、可扩展的 PowerShell 终端增强体验。

[![MIT License](https://img.shields.io/badge/License-MIT-blue.svg)](ShellPrompt/LICENSE)
[![PowerShell](https://img.shields.io/badge/PowerShell-7.6+-blue.svg)](https://github.com/PowerShell/PowerShell)
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

- **加载动画 (ProgressSpinner)** — 5 套 unicode 样式 (Braille / Ascii / Blocks / Dots / Arrows) 在耗时操作期间提供单行动态反馈；采用纯函数 + I/O 包装分层，v2.0 起单轨走 Spectre.Console (不依赖 `Start-ThreadJob`)。[`Show-ProgressSpinner.ps1`](ShellPrompt/Private/Show-ProgressSpinner.ps1)
- **`Invoke-WithProgress` 封装** — 接受 `-ScriptBlock` + 可选 `-PollScript`，内部 spin 循环 + 超时（默认 60s）+ 异常重拋，集成于 `Start-TmuxSession` 入口的 SSH 探测与远程会话刷新。([`Invoke-WithProgress.ps1`](ShellPrompt/Private/Invoke-WithProgress.ps1))
- **欢迎 Banner 纯函数** — `New-WelcomeBanner` 构造行数组，`Get-RandomQuote` 带 mtime 缓存避免反复读盘；`Start-TmuxSession` 入口处展示运行主题 banner（主机名+语录）。([`New-WelcomeBanner.ps1`](ShellPrompt/Private/New-WelcomeBanner.ps1))
- **输入提示 (InputPrompt)** — 支持默认值 / 校验器（bool / hashtable / throw 三种契约）/ Esc 取消 / Ctrl+U 清空，提取 `Update-InputBuffer` / `Test-InputValidation` 纯函数便于测试。([`Show-InputPrompt.ps1`](ShellPrompt/Private/Show-InputPrompt.ps1))
- **菜单状态机 (MenuMachine)** — P1 阶段实现的纯函数状态机驱动 `Show-HostSelector` 与 `Show-SessionManager`，统一处理键盘 / 过滤 / 焦点切换。([`Invoke-MenuMachine.ps1`](ShellPrompt/Private/Invoke-MenuMachine.ps1))
- **动态帮助面板** — 根据当前动作集合动态生成键位提示。([`New-DynamicHelpPanel.ps1`](ShellPrompt/Private/New-DynamicHelpPanel.ps1))
- **状态徽章** — Online / Attached / Detached / NetworkError / Pending / Disabled / Warning 七种状态点。([`New-StatusBadge.ps1`](ShellPrompt/Private/New-StatusBadge.ps1))

### 现代工具链集成

- **Starship Prompt 延迟加载** — 跨 Shell 提示符，显示 git 上下文、Node 版本等信息，推迟到首次交互前加载。
- **Fnm (Node.js) 自动切换** — 进入项目目录时自动切换对应 Node 版本。
- **wttr.in 提示符天气** — [`Get-WttrWeather`](ShellPrompt/Private/Get-WttrWeather.ps1) 提供一行 ASCII 天气（如 `Shanghai: 🌫 +18°C`），模块级 10 分钟缓存 + 5 秒超时 + 错误兜底，零额外依赖（系统 `curl.exe` 优先，回退 `Invoke-RestMethod`）。详见下方 [提示符天气](#-提示符天气) 章节。

### 工作流便利

- **`Invoke-Reload`** — 一键重载 PowerShell Profile。[`Invoke-Reload.ps1`](ShellPrompt/Public/Invoke-Reload.ps1)
- **全局别名** — `ll` (Get-ChildItem)、`which` (where.exe)、`sss` (Start-TmuxSession)、`ssh-copy-id` (Copy-SshPublicKey)。

### 🌤️ 提示符天气

[`Get-WttrWeather`](ShellPrompt/Private/Get-WttrWeather.ps1) 面向 PowerShell 提示符调用的轻量天气获取函数，输出单行字符串，适合拼接到 `prompt` 渲染中：

```powershell
PS> Get-WttrWeather
Shanghai: 🌫 +18°C
```

**核心特性**

| 维度 | 行为 |
|------|------|
| 输出格式 | `Short`（默认 `?format=3`，单行） / `Full`（三日 ASCII 横幅） / `CustomUrl`（透传 `-Url`） |
| HTTP 客户端 | 优先 `curl.exe`（Win10 1803+ / Server 2019+ / Linux 自带），缺失回退 `Invoke-RestMethod` |
| 缓存 | 模块作用域 `$script:_WttrCache`，默认 10 分钟（`-CacheMinutes` 可调，`0` 强制刷新） |
| 超时 | 5 秒（`-TimeoutSeconds` 可调，1–60） |
| 错误兜底 | 超时 / 网络失败 / 远端空响应 一律返回 `""` + `Write-Verbose` 诊断，**绝不抛异常污染 prompt** |
| 依赖 | 零额外依赖；无 curl 时自动回退到 PowerShell 内置 HTTP 客户端 |

#### 方式一：项目接管 prompt（默认推荐，不需任何配置）

本项目已在 [`Microsoft.PowerShell_profile.ps1:147`](Microsoft.PowerShell_profile.ps1:147) 的 `function global:prompt` 包装器中集成 wttr 注入逻辑，零用户配置：

1. 调用 Starship 原始 prompt 拿到完整字符串（保留 `< user@host >` / tmux 状态 / Git 上下文等所有段）。
2. 用 `Get-WttrWeather -Format Short` 拉取一行天气（模块级 10 分钟缓存，首次触发 wttr.in HTTP）。
3. 用 `[regex]::Replace($base, '<\s*\S+@\S+\s*>', $wttr)` 把 `< user@host >` 段就地替换。
4. 任何环节失败（模块未加载 / wttr 返回空字符串 / 异常）都退回 Starship 原 prompt，**绝不会让 prompt 整体消失**。

**预期渲染**（以 Starship 默认 `+--< user@host >--[ path ]--...` 模板为例）：

```text
+--Shanghai: 🌫 +18°C--[ 33098 ]--[ TMUX 管理器 [debian] ] [● tmux 3.5a] [会话: 1 (附=0 分=1)]
```

> **关于本条原则冲突**：本做法**违反** [AGENTS.md](AGENTS.md) 中"`Microsoft.PowerShell_profile.ps1` 只做模块加载/环境初始化，不放业务逻辑"原则。触发原因：用户连续两次使用 `starship.toml` 接入都未生效，调试无进展，这是当前唯一可行路径。详见 [`Microsoft.PowerShell_profile.ps1`](Microsoft.PowerShell_profile.ps1) 顶部注释。

#### 方式二：修改 `~/.config/starship.toml`（可选回退）

如果你坚持使用 Starship 自定义模块，可在用户 `~/.config/starship.toml` 中加入：

```toml
# 1. 关闭 Starship 自带的 tmux 模块
[tmux]
disabled = true

# 2. 新增自定义模块调用本项目的 Get-WttrWeather
[custom.wttr]
command = "powershell -NoProfile -Command \"Get-WttrWeather\""
when = "shell == 'powershell'"
format = "[$output]($style) "
style = "bold yellow"
```

> **⚠️ 已知坑**：Starship `custom.*` 模块在 PowerShell 宿主的 PATH / 编码环境下偶发不生效（用户实测两次都未生效）。如未生效，直接使用方式一（项目接管 prompt，无需任何额外配置）。

#### 回滚方式一（如需纯 Starship 渲染）

如需禁用项目接管的 wttr 注入，回到纯 Starship 渲染：

```powershell
# 在 Microsoft.PowerShell_profile.ps1 中，将 function global:prompt { ... } 整段替换为：
function global:prompt {
    try { return (& $global:OriginalPrompt) } catch { return "PS> " }
}
```

或直接 `git checkout -- Microsoft.PowerShell_profile.ps1` 回滚本文件。

## 🚀 安装

### 前置依赖

| 依赖 | 说明 |
|------|------|
| PowerShell 7.6+ | **唯一支持版本**。`ShellPrompt.psd1` 声明 `PowerShellVersion = '7.6'`；Windows PowerShell 5.1 已不再支持。抬高门槛的原因是交互菜单主轨依赖的 [`PSTui`](Modules/PSTui/1.0.5/README.md) 是 .NET 10 二进制模块, 要求 PS 7.6+ |
| `PSTui` | 交互菜单主轨, 仓库内置于 `Modules/PSTui/`。**缺失/版本冲突/非交互宿主时自动降级为自研 ANSI 菜单**, 不会导致模块加载失败 |
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
> 远超本项目"小而深"模块边界;且 Pester 虚高 + scope 链路过深,
> 实测 7 次重试仍无法稳定 fire。手动 `Invoke-Reload` 成本低、可预测。
>
> **推荐编辑器工作流**: VSCode / vim 配 `chokidar` / `watchexec` 监听 `ShellPrompt/*.ps*`,
> 存盘后自动调 `Invoke-Reload -Quiet`(项目根 `.vscode/settings.json` 或 `~/.config/watchexec/config.toml`)。

## 🏗️ 架构

### 目录结构

```
PowerShell/
├── Microsoft.PowerShell_profile.ps1   # 入口：仅处理模块加载与启动配置
├── AGENTS.md                          # AI 代理开发约束（根路由）
├── README.md
├── data/
│   └── quotes.txt                     # 随机语录数据
├── docs/                              # 文档目录
│   ├── agents/                        # AGENTS.md 路由的细分子规约
│   │   ├── architecture.md            # 目录职责、兼容性与降级
│   │   ├── development.md             # 命名、函数拆分、错误处理、配置
│   │   ├── domain-ssh-tmux.md         # SSH / tmux 领域红线
│   │   ├── testing.md                 # 测试与文档义务
│   │   └── commit-convention.md       # 提交信息规范
│   └── UI-Refactor-Plan.md
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
        ├── ConvertTo-TmuxRefreshSelection.ps1 # 「刷新会话列表」选中项契约
        ├── Get-GridViewColumnPlan.ps1     # GridView 列可见性与 keyColumn 规划
        ├── Get-GridViewHostRow.ps1        # GridView 主机选择行构造
        ├── Get-GridViewManagerRow.ps1     # GridView 会话管理行构造
        ├── Get-KeyboardFilter.ps1         # [P1] PSReadLine 键盘事件过滤
        ├── Get-SshArgs.ps1                # SSH 参数生成器
        ├── Get-SshConfigHosts.ps1         # SSH config 主机解析
        ├── Get-SshSocketPath.ps1          # SSH socket 路径
        ├── Get-TmuxRefreshedSession.ps1   # 刷新时重新拉取会话列表
        ├── Get-TmuxSessionGridRow.ps1     # GridView 会话列表行构造（含刷新行）
        ├── Get-TmuxSessionMenuOption.ps1  # ANSI 会话列表项构造（含刷新项）
        ├── Get-TmuxSessionStateText.ps1   # 「● 已附着 / ○ 已分离」状态文案
        ├── Get-TmuxSessionSummary.ps1     # 「附 N / 分 M」标题计数
        ├── Get-TmuxSessions.ps1           # 远程 tmux 探测与列表
        ├── Initialize-Config.ps1          # 配置初始化与缓存
        ├── Initialize-GridViewColorScheme.ps1 # GridView 配色初始化（失败仅告警）
        ├── Invoke-ConsoleMenu.ps1         # 终端交互式菜单 UI
        ├── Invoke-GridViewMenu.ps1        # GridView 主轨菜单（主机/会话/会话列表）
        ├── Invoke-MenuMachine.ps1         # [P1] 菜单状态机（驱动 HostSelector/SessionManager）
        ├── Invoke-SshCaptureOutput.ps1    # SSH 异步输出捕获
        ├── Invoke-SshCommand.ps1          # SSH 命令调度（主线逻辑）
        ├── New-DynamicHelpPanel.ps1       # [P1] 动态生成键位提示
        ├── New-StatusBadge.ps1            # [P1] 状态徽章（Online/Attached/Detached/...）
        ├── New-TmuxSession.ps1            # 创建新 tmux 会话
        ├── New-WelcomeBanner.ps1          # [P2] 欢迎 Banner 纯函数（主机名+随机语录）
        ├── Remove-TmuxSession.ps1         # 删除 tmux 会话
        ├── Reset-TerminalMode.ps1         # 终端编码/TERM 恢复
        ├── Restore-GridViewSelection.ps1  # GridView 选中项归一化与隐藏字段恢复
        ├── Save-OriginalTerminalState.ps1 # 终端状态保存
        ├── Show-InputPrompt.ps1           # [P2] 输入提示（默认值/校验器/Esc 取消/Ctrl+U 清空）
        ├── Show-ProgressSpinner.ps1       # [P2] 加载动画 + Invoke-WithProgress 封装
        ├── Show-TmuxSessionList.ps1       # 会话列表（含「刷新」原地重绘循环）
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

### v2.0 Spinner/Progress 单轨 Spectre 调度

spinner 与 ScriptBlock 进度动画在 v2.0 起改为 **单轨 Spectre.Console 架构**。模块清单声明 `PowerShellVersion = '7.6'`，`PwshSpectreConsole` 是**硬依赖**（缺失即 `ShellPrompt.psm1` 抛终止错误，不做静默降级）。

> **重要区分**: 进度动画是**单轨 Spectre**, 但交互菜单是**双轨 (PSTui / ANSI)**, 见下文「交互菜单后端 (PSTui 主轨 + ANSI 降级轨)」。Spectre.Console **不负责菜单渲染**, 只负责 spinner、进度动画以及菜单上方的提示行/删除确认。

| 路径 | 渲染后端 | 触发条件 | 存在原因 |
|------|----------|----------|----------|
| **同步封装** | `Invoke-SpectreCommandWithStatus` | 默认 | Spectre 完整动画生命周期 |
| **轮询封装** | `Show-ProgressSpinner` 单帧循环 | `-PollScript` / `-SuppressConsole` / 显式 `<60` 的 `-TimeoutSeconds` | Spectre API 无 poll / 无硬超时 / 无法抑制控制台 |

`Show-ProgressSpinner` 已废弃 `-ForceLegacy` 参数与 `Test-SpectreSpinnerAvailable` 探测函数；`-ForceLegacy` 不再是有效参数。

**Spectre markup 转义**：`Write-SpectreHost -Message` 会按 Spectre markup 解析，裸 `[` 被当作样式标记。所有拼好的渲染行在输出前统一经 `ConvertTo-SpectrePlainText` 做 `[` → `[[` 转义，避免 ANSI 序列（`ESC[38;2;…m`、`ESC[0K`）被吞。

**风格映射表** (调用方 `-Style` → Spectre.Spinner.Known)：

| ShellPrompt 样式 | Spectre 内置 | 说明 |
|------------------|--------------|------|
| `Dots` | `Dots6` | 6 点脉冲 (用户原始诉求) |
| `Braille` | `Dots3` | 盲文点阵最接近的 Spectre 等价物 |
| `Ascii` | `Ascii` | 1:1 |
| `Blocks` | `Block1` | 进度块最接近的 Spectre 等价物 |
| `Arrows` | `Arrow` | 1:1 |
| 其它 / 未传 | `Dots6` | 安全回退 |

**已知约束**：`Invoke-SpectreCommandWithStatus` 底层 `Start-AnsiConsoleStatus` 无硬超时。调用方需要超时保护时，**显式传入小于 60 的 `-TimeoutSeconds`**，调度层会自动路由到轮询封装（带硬超时 + TimeoutException），或在调用外层用 `Stopwatch` 自己包。

## 🎛️ 交互菜单后端（PSTui 主轨 + ANSI 降级轨）

`sss`（[`Start-TmuxSession`](ShellPrompt/Public/Start-TmuxSession.ps1)）里的「主机选择」和「会话管理」两个交互菜单是**双轨**的。模块加载期由 [`Get-ConsoleUiBackend`](ShellPrompt/Private/Get-ConsoleUiBackend.ps1) 判定一次，结果存入 `$script:ConsoleUiBackend`。

| 后端 | 实现 | 触发条件 |
|------|------|---------|
| `GridView`（主轨） | [`Modules/PSTui`](Modules/PSTui/1.0.5/README.md) 的 `Out-ConsoleGridView` 表格视图（[`Invoke-GridViewMenu.ps1`](ShellPrompt/Private/Invoke-GridViewMenu.ps1)） | PS 7.6+、`PSTui` 可发现、无同名命令冲突、`Terminal.Gui` 主版本为 2、stdin 未重定向 |
| `AnsiFallback`（降级轨） | 自研 ANSI 实时过滤菜单（[`Invoke-AnsiMenu.ps1`](ShellPrompt/Private/Invoke-AnsiMenu.ps1)） | 上述任一条件不满足 |

**降级只 `Write-Warning` 并说明原因，绝不 `throw`** —— 菜单不可用不应该让整个模块加载失败。典型降级原因：非交互宿主（管道 / CI / 输入重定向）下 `Out-ConsoleGridView` 会抛 `Not supported in this environment`。

### 两条轨的对外契约

[`Show-HostSelector`](ShellPrompt/Private/Show-HostSelector.ps1) / [`Show-SessionManager`](ShellPrompt/Private/Show-SessionManager.ps1) 只做分发，两轨返回**同构**的 `PSCustomObject`（`.Value` 为选中值，`$null` 表示用户取消）。调用方无需感知后端。

### 会话管理菜单文案（Desc）

会话管理菜单的**说明列（Desc）**在两条轨上保持一致，均为精简后的短文案；命令名、`Action` 键与「选中 → 动作」映射不受影响。

| Action | Label | Desc |
|--------|-------|------|
| `Attach` | 附着/恢复 tmux 会话 | `附到 tmux 会话` |
| `New` | 创建新 tmux 会话 | `创建 tmux 会话` |
| `Remove` | 删除 tmux 会话 | `删除 tmux 会话` |
| `Ssh` | 直接 SSH 登录 | `直接 SSH 登录` |
| `Refresh` | 刷新会话列表 | `刷新会话` |

> 降级轨的实现见 [`Invoke-AnsiMenu.ps1`](ShellPrompt/Private/Invoke-AnsiMenu.ps1)，主轨的实现见 [`Invoke-GridViewMenu.ps1`](ShellPrompt/Private/Invoke-GridViewMenu.ps1)。修改文案时两处需同步，避免两轨显示不一致。

### 会话列表的「已附着 / 已分离」状态

`sss` 的会话列表（GridView 主轨与 ANSI 降级轨一致）会为每个 tmux 会话显示一个 **State** 状态列，用于区分该会话当前是否被终端附着：

| 状态 | 徽章 | 含义 |
|------|------|------|
| 已附着 | `● 已附着` | 该 tmux 会话已被某个客户端附着，屏幕内容正在被实时共享；对它执行 `attach` 会提示 `sessions should be nested with care` |
| 已分离 | `○ 已分离` | 该会话当前无客户端附着，可安全 `attach` 进入 |

标题栏的 **「附 N / 分 M」** 与之配套：`N` = 已附着会话数，`M` = 已分离会话数。两个数字直接来自状态列的判定结果，与下方表格逐行一致。

状态数据的来源与优先级（见 [`Get-TmuxSessions.ps1`](ShellPrompt/Private/Get-TmuxSessions.ps1)）：

1. **机器可读路径（首选）**：`tmux list-sessions -F "TMUX_SESSION #{session_attached} #{session_windows} #{session_name}"`，直接取 tmux 的权威字段 `session_attached`。**会话名放在格式串最后**，因此会话名中含空格、冒号（如 `my session`、`a:b`）都不会被误切分。
2. **`tmux ls` 容错回退**：机器可读路径不可用（老版本 tmux / 环境异常）时，回退到宽松正则解析 `tmux ls` 文本输出，能识别 `[attached]` 方括号形态、`window`/`windows` 单复数、缺 `(created …)` 的精简形态以及尾部附加字段。
3. **异常降级**：tmux 未安装、无 server 运行、输出为空或不可解析时，返回**空集合**并给出告警，**不会抛异常**，菜单照常以「暂无会话」打开。

> State 列与「附 N / 分 M」在会话列表打开的**那一刻**求值。tmux 侧的附着状态随时可能变化（例如你在另一个标签页 attach 了某个会话），所以表格是**打开时快照**，不会自行变化。

### 「刷新会话列表」的使用时机

因为列表是打开时的快照，若状态与实际不符（例如刚在别的终端 attach 过），可在列表里手动触发一次刷新。

| 后端 | 刷新入口 | 表现 |
|------|---------|------|
| `GridView`（主轨） | 表格最后一行 `⟳ 刷新会话列表` | 选中后清屏**原地重绘**整张表，仍停留在会话列表 |
| `AnsiFallback`（降级轨） | 列表末项 `⟳ 刷新会话列表` | 同样清屏原地重绘 |

刷新语义（两轨完全一致）：

- **仅由用户手动触发**。菜单打开期间**没有任何定时器 / 后台轮询**，不占用额外进程或线程，也不会在后台悄悄刷新。
- 刷新会**重新执行一次 `tmux` 查询**，拿到最新的附着状态与窗口数，并据此重算「附 N / 分 M」。
- 刷新是**原地重绘**，不会退出菜单、不会回到上一级菜单、不需要重新输入主机名。
- 刷新后若已经没有可用会话，会给出告警并返回上一层（等价于「无可选会话」）。
- **对外契约不变**：两轨仍返回带 `.Value` 的 `PSCustomObject` 或 `$null`；刷新项通过独立的刷新标记（`.IsRefresh` / 内部哨兵值）区分，不会与真实会话名混淆。

典型使用场景：

- 你在另一个终端标签页 `tmux attach` 了某个会话 → 回到本终端打开会话列表 → 选 `⟳ 刷新会话列表` → State 列与「附 N / 分 M」立即更新。
- 刚用 `tmux kill-session` 删掉了会话，但列表还显示旧记录 → 刷新一次即可看到最新结果。
- 在列表里误选了某行并进入会话 → 退出后重新打开列表即取新快照，无需手动刷新。

### 强制指定后端（调试用）

```powershell
# 仅测试注入 / 故障排查使用; 默认取启动期检测结果
$sel = & (Get-Module ShellPrompt) { Show-HostSelector -Hosts $hosts -Backend 'AnsiFallback' }

# 查看当前判定结果
& (Get-Module ShellPrompt) { $script:ConsoleUiBackend | Format-List }
```

### 配置项（`$HOME/.ShellPrompt/config.ps1`）

| 键 | 默认 | 说明 |
|----|------|------|
| `UI.Backend` | `Auto` | `Auto` / `GridView` / `AnsiFallback`。非 `Auto` 时跳过全部自动检测 |
| `UI.GridViewFocus` | `Table` | `Table` = 焦点在表格; `Filter` = 焦点在筛选框（对应旧 ANSI 菜单的 `Q1=A` 实时过滤手感） |
| `UI.GridViewFullScreen` | `$false` | `Out-ConsoleGridView` 是否全屏渲染 |

### GridView 配色（Terminal.Gui `Scheme` 槽位）

主轨表格的配色由 [`Initialize-Config.ps1`](ShellPrompt/Private/Initialize-Config.ps1) 的 `UI.Theme` 域下发，落地逻辑在 [`Set-TgColorScheme.ps1`](ShellPrompt/Private/Set-TgColorScheme.ps1)：**就地改写** `SchemeManager` 里**已存在**的 `Base` / `Menu` 两个方案实例（不新增方案名、不写 `ThemeManager.Theme`——在 TG 2.4.10 上该组合会让内部字典与 `Theme` 失配）。

键 | 默认 | 说明 |
|----|------|------|
`UI.Theme.Enabled` | `$true` | `false` 时完全不触碰 Terminal.Gui 静态 API |
`UI.Theme.Name` | `@('Base','Menu')` | 覆写目标方案名（不存在时自动回退 `Base`）；单个字符串会被自动规范化为数组 |
`UI.Theme.Slots` | 见下表 | 槽位名 → `@{ Fg = 'R,G,B'; Bg = 'R,G,B' }` |

槽位（TG 2.4.10 上反射实测可写，共 10 个可视槽位；`Code*` 语法高亮槽位不参与菜单故不配置）：

槽位 | 默认色 | 作用 |
|------|--------|------|
`Normal` | `137,209,133` / `30,30,30` | 正文单元格、无焦点时的列头、列间竖线 |
`HotNormal` | `159,177,159` / `30,30,30` | 快捷键热区 |
`Focus` | `20,20,20` / `112,199,209` | **聚焦列头 + 表格有焦点时的选中行** |
`HotFocus` | `20,20,20` / `130,215,220` | 其它 View 的聚焦热区（TableView 不读取） |
`Active` | `20,20,20` / `112,199,209` | **焦点不在表格时的选中行** |
`HotActive` | `20,20,20` / `130,215,220` | 激活项热区（TableView 不读取） |
`Highlight` | `20,20,20` / `112,199,209` | 高亮标记（鼠标热区，TableView 不读取） |
`Editable` | `230,180,80` / `30,30,30` | 可编辑区 |
`ReadOnly` | `159,177,159` / `30,30,30` | 只读行 |
`Disabled` | `100,100,100` / `30,30,30` | 禁用行 |

**迁移说明（高亮统一）**：TG 2.4.10 的 `TableView.RenderRow` 用 `hasFocus ? scheme.Focus : scheme.Active` 决定选中行取色，而 `RenderHeaderMidline` 用 `scheme.Focus` 画聚焦列头——`Focus` 被**列头与选中行共用**。这正是「焦点在表格时选中行是浅色、焦点移到过滤框后又变成青色」的根因。默认配置因此把 `Focus` 与 `Active` 设为**完全相同**的颜色（Cyan 底 + 近黑字），使两种焦点状态下的选中行高亮一致。副作用：表格有焦点时列头也是青色条；过滤框文字取 `Focus`（TG 的 `TextField` 把 role Normal 映射到 role Focus），因此过滤框文字为近黑字配 Cyan 底。

> 只想自定义高亮色：改 `UI.Theme.Slots` 里的 `Focus` 与 `Active`，**两个都要改**才能保持统一。未知或不可写的槽位名会被静默跳过，不会报错。

### 能力回退清单（主轨相对降级轨的损失）

| 原 ANSI 菜单能力 | GridView 主轨现状 | 补偿手段 |
|---|---|---|
| 行级红色 / 危险项高亮 | PSTui 未开放 Color/Theme API | `State` 列文本（`⚠ 危险` / `⚠ 备选` / `● last`） |
| 底部帮助文本行 | 表格视图无底部帮助区 | 菜单**上方**一行 Spectre 提示（`↑↓ 选择  Enter 确认  Esc 退出`） |
| `Q1=A` 实时增量过滤 | 无键盘级过滤回调 | `-Focus Filter` 表格筛选框（`UI.GridViewFocus = 'Filter'`） |
| `Disabled` 行灰显 | 不支持渲染禁用态 | `State` 列标注 + 选中后**阻断**并提示 |
| 独立「退出」行 | 表格不再放 Exit 行 | `Esc` / `Ctrl-C` 退出，返回 `$null` |

### 性能特征与实测数据（主轨 vs 降级轨）

| 维度 | `GridView` 主轨 | `AnsiFallback` 降级轨（加固后） |
|---|---|---|
| 渲染方式 | PSTui `Out-ConsoleGridView` 表格视图, 宿主内一次性重绘 | 逐行绝对定位覆盖 (`ESC[<行>;1H` + `ESC[2K`) |
| 每次按键重绘量 | 整表重绘, 由 TG 内部批处理 | 满帧 `21` 行/帧 (Header 4 + Main N + Footer 2), 帧变矮时自动擦除残留行 |
| 整屏清屏 | 无此机制 | **仅首帧**执行一次 `[Console]::Clear()`; 其余帧只覆盖行, 不再整屏闪烁 |
| 非 TTY / stdout 重定向 | 自动降级到 ANSI 轨 | `Clear-AnsiScreen` 捕获 `句柄无效。` 异常, **不再刷屏** (同一次 200 帧对照: 裸 `Clear()` 产生 stderr `98,200 字节` → 加固后 `0` 字节) |
| 单个菜单项渲染耗时 | 不适用 (表格单元格) | 完整颜色表 `198.68 µs/次`; 颜色表残缺时 `1045.44 µs/次` (补全后不再逐项回查配置, 渲染结果逐字节一致) |

**结论**: 「ui 卡顿」在正常终端下**已消解** —— 三个交互菜单默认全部走 `GridView` 主轨, 手写 ANSI 只在降级场景出现。降级轨此前确实存在「每按键整屏 `Clear()` + 21 行全帧重绘 + 颜色表缺失导致逐项回查配置」的叠加开销, 已按低成本方式加固 (不触碰主轨):

- 新增 [`Clear-AnsiScreen.ps1`](ShellPrompt/Private/Clear-AnsiScreen.ps1), 所有整屏清屏调用点统一走它, 非 TTY 下不抛异常;
- 渲染前由 `Resolve-MenuColorTable` 一次性补全 7 个语义色键, 消除逐项 `Get-CachedConfig` 回查;
- `Show-AnsiLayout` 改为首帧清屏 + 逐行覆盖, 帧变矮时擦除残留行。

> 同口径实测: 满帧 21 行重绘 `3.5612 ms/帧` vs 只重绘 3 行 `0.3769 ms/帧` (约 9.4 倍)。以上均为 stdout 被重定向到文件时的数据 (含写文件开销), 绝对值偏大但相对比较有效; **真实交互终端的手感无法在自动化环境量化** (stdin 被重定向), 需人工按 [`docs/UI-Refactor-Plan.md` 附录 C.7](docs/UI-Refactor-Plan.md) 的验收清单确认。

### 删除会话的二次确认

`Remove-TmuxSession` 在选中会话后、`tmux kill-session` 之前插入 [`Read-SpectreConfirm`](Modules/PwshSpectreConsole/2.6.3/PwshSpectreConsole.psm1) 阻断式确认（默认答案 `n`）。确认不可用（非交互终端）时**按「不删除」处理**，绝不默认放行。

## 🛠️ 开发者指南

以下约束引自 [`AGENTS.md`](AGENTS.md) 及其路由的 [`docs/agents/`](docs/agents/) 子规约，所有贡献者必须遵守。

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

> - **Testing**: Before submitting changes, verify module loading (`Import-Module ./ShellPrompt`). Run tests via `Invoke-Pester` (Assume Pester v5 syntax). Run PSScriptAnalyzer via `Invoke-ScriptAnalyzer -Path ./ShellPrompt -Recurse -Settings ./ShellPrompt/Settings.ScriptAnalyzer.psd1` (`-Path` is mandatory). Any changes involving profile loading, SSH, or tmux MUST be flagged for manual testing.

> **PSSA 已知约束**：[`Settings.ScriptAnalyzer.psd1`](ShellPrompt/Settings.ScriptAnalyzer.psd1) 中 `PSUseCorrectCasing` 的 `CheckCommands` 被置为 `$false`。原因是 PSScriptAnalyzer 1.25.0 的该规则在读取命令参数元数据时，会实例化 [`PwshSpectreConsole`](Modules/PwshSpectreConsole/2.6.3/PwshSpectreConsole.psm1) 的动态 `ValidateSet` 值生成器，而该生成器需要 Runspace，PSSA 在无 Runspace 的线程中调用即抛 `There is no Runspace available to run scripts in this thread`，导致**整个被扫描文件的扫描结果作废**（不只是该文件）。关闭后关键字 / 操作符 / 别名的大小写检查仍然生效，仅命令名与参数名的大小写检查被关闭。

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
