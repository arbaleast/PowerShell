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

- **加载动画 (ProgressSpinner)** — 5 套 unicode 样式 (Braille / Ascii / Blocks / Dots / Arrows) 的帧序列能力；采用纯函数 + I/O 包装分层，v2.0 起渲染单轨走 Spectre.Console (不依赖 `Start-ThreadJob`)，v2.1 起该文件**无生产调用方**（仅测试覆盖），其样式映射 `Get-SpinnerStyleMapping` 仍由 `Invoke-WithProgress` 复用。[`Show-ProgressSpinner.ps1`](ShellPrompt/Private/Show-ProgressSpinner.ps1)
- **`Invoke-WithProgress` 封装** — 接受 `-ScriptBlock` + 可选 `-PollScript`，同步路径显示 Spectre 动画、轮询路径静默执行（带硬超时，默认 60s）+ 异常重拋，集成于 `Start-TmuxSession` 入口的 SSH 探测与远程会话刷新。([`Invoke-WithProgress.ps1`](ShellPrompt/Private/Invoke-WithProgress.ps1))
- **欢迎 Banner 纯函数** — `New-WelcomeBanner` 构造行数组，`Get-RandomQuote` 带 mtime 缓存避免反复读盘；`Start-TmuxSession` 入口处展示运行主题 banner（主机名+语录）。([`New-WelcomeBanner.ps1`](ShellPrompt/Private/New-WelcomeBanner.ps1))
- **交互菜单 (GridView 单轨)** — 主机选择 / 会话管理 / tmux 会话列表三个菜单统一走 PSTui `Out-ConsoleGridView` 主轨，表格行、列裁剪与选中结果归一化由 GridView 私有函数负责。([`Invoke-GridViewMenu.ps1`](ShellPrompt/Private/Invoke-GridViewMenu.ps1))
- **会话状态文案** — 「● 已附着 / ○ 已分离」等状态文案由单一事实来源函数产出，菜单各入口不再各写一份。([`Get-TmuxSessionStateText.ps1`](ShellPrompt/Private/Get-TmuxSessionStateText.ps1))
- **GridView 配色** — 语义色键统一经 `Resolve-ColorTable` 解析（调用方覆盖 → 配置层默认值），并初始化为 Terminal.Gui `Scheme` 槽位。([`Resolve-ColorTable.ps1`](ShellPrompt/Private/Resolve-ColorTable.ps1))

### 现代工具链集成

- **Starship Prompt** — 跨 Shell 提示符，显示 git 上下文、Node 版本等信息。
- **Fnm (Node.js) 自动切换** — 进入项目目录时自动切换对应 Node 版本。
- **wttr.in 交互菜单标题区天气** — 三个交互菜单 (SSH 主机选择器 / tmux 管理器 / tmux 会话列表) 的 PSTui 窗口**标题区**自动追加一行 wttr 天气短串 (如 `Shanghai: 🌫 +18°C`), 顶部居中显示. 复用 [`Get-WttrWeather`](ShellPrompt/Private/Get-WttrWeather.ps1) 10 分钟缓存 + 5 秒超时 + 错误兜底. 详见下方 [交互菜单标题区天气](#-交互菜单标题区天气) 章节.

### 工作流便利

- **`Invoke-Reload`** — 一键重载 PowerShell Profile。[`Invoke-Reload.ps1`](ShellPrompt/Public/Invoke-Reload.ps1)
- **全局别名** — `ll` (Get-ChildItem)、`which` (where.exe)、`sss` (Start-TmuxSession)、`ssh-copy-id` (Copy-SshPublicKey)。

### 🌤️ 交互菜单标题区天气

三个交互菜单 (SSH 主机选择器 / tmux 管理器 / tmux 会话列表) 的 PSTui **窗口标题区**自动追加一行 wttr 天气短串 —— 由 [`Invoke-GridViewMenu.ps1`](ShellPrompt/Private/Invoke-GridViewMenu.ps1) 的私有 helper `Get-WttrTitleSuffix` 在三个 `Invoke-GridViewPrompt` 调用点 (`Invoke-GridViewHostSelector` / `Invoke-GridViewSessionManager` / `Invoke-GridViewSessionList`) 拼装 `-Title` 参数之前判定 `$script:Config.Weather.Enabled`; 启用时调 `Get-WttrWeather -Format CustomUrl -Url 'https://wttr.in/?format=j1' -CacheMinutes 10` (复用 10 分钟缓存), 自解析 j1 拿到 `nearest_area[0].areaName[0].value` (城市名) + `current_condition[0].temp_C` (温度) + `current_condition[0].weatherDesc[0].value` (天气描述), 自拼成 ` - <City>: <Desc> <Temp>°C` 片段附加到标题末尾. 失败/超时/禁用时静默跳过, 绝不抛异常, 绝不污染主菜单.

> 这一版的 `Write-GridViewHint` 不再渲染天气片段, 完全交给 PSTui 标题区做; 提示行只保留按键说明 (`↑↓ 选择  Enter 确认  Esc 退出`), 不出现重复渲染.

> 端点选 `?format=j1` 而非 `?format=3`: 短格式在 IP 定位下会回退到 `lat,lon: 图标 温度`, 丢城市名 (wttr.in 对 nearest_area 的渲染策略不稳定). j1 一次性返回 nearest_area + current_condition, 我们自拼字符串, 行为完全可预测. 详见 `ShellPrompt/CHANGELOG.md` `[Unreleased] / Fixed` "wttr.in 端点选择：标题区没城市名" 条目.

> 天气描述已中文化 (客户端字典); 城市名跟随 wttr.in `nearest_area` 服务 (可能仍为英文拼音, IP 定位命中 `Chiuhuahsien` 这种). 中文化靠内置字典 (`Get-WttrWeatherDescMap`, 覆盖 `Smoky haze` / `Mist` / `Haze` / `Sunny` / `Cloudy` / `Partly Cloudy` / `Clear` / `Overcast` / 各种 Rain/Snow/Thunder 等约 50 条), 未命中回退英文并 `Write-Verbose` 提示; 用户可在 `Weather.ExtraWeatherDescMap` 追加/覆盖条目. 详见 `ShellPrompt/CHANGELOG.md` `[Unreleased] / Fixed` "PSTui 标题区天气描述中文化" 条目.

**典型输出** (`sss` 主机选择菜单窗口标题区):

```text
SSH 主机选择器 (3) - Chiuhuahsien: 烟雾 26°C
```

**典型输出** (`sss` → tmux 管理器窗口标题区):

```text
TMUX 管理器 [debian] - tmux 3.5a - 会话 2 (附 1 / 分 1) - Chiuhuahsien: 烟雾 26°C
```

#### 配置项（`$HOME/.ShellPrompt/config.ps1`）

`Weather` 配置域定义在 [`Initialize-Config.ps1`](ShellPrompt/Private/Initialize-Config.ps1):

| 键 | 类型 | 默认值 | 说明 |
|----|------|--------|------|
| `Weather.Enabled` | `bool` | `$true` | 总开关; `$false` 时 3 个菜单标题区均不追加 wttr 片段 |
| `Weather.ExtraWeatherDescMap` | `[ordered]@{}` | `{}` | 用户自定义 wttr.in `weatherDesc` 英文 → 中文映射; 键 = 英文短语 (匹配时 `.ToLower()`), 值 = 中文; 同名键覆盖内置字典 |

```powershell
# ~/.ShellPrompt/config.ps1
$Config.Weather.Enabled = $false                                          # 禁用交互菜单标题区天气

# 追加/覆盖 wttr 描述中文 (同名键覆盖内置字典)
$Config.Weather.ExtraWeatherDescMap = [ordered]@{
    'smoky haze' = '烟霞'                                                  # 覆盖内置 'Smoky haze' → '烟雾'
    'my custom desc' = '自定义描述'                                        # 用户自创的本地化条目
}
```

#### 公开命令 `Update-Weather`

[`Update-Weather`](ShellPrompt/Public/Update-Weather.ps1) 强制刷新 wttr Short 缓存并立即 `Write-Host` 渲染 —— 适用于手动验证 wttr.in 是否可达、或在终端里临时拉一次最新天气:

```powershell
PS> Update-Weather
Shanghai: 🌫 +18°C
```

任何时候都可直接调用, 不影响交互菜单标题区的渲染流程 (调用方不感知).

> 注：`Update-Weather` 与菜单标题区走两条不同 HTTP 路径（短格式 `?format=3` vs j1 自拼 `?format=j1&lang=zh`），不共享缓存；菜单标题区走 `Get-WttrTitleSuffix` 内置中文字典翻译。

#### 降级场景

| 场景 | 行为 |
|------|------|
| `Weather.Enabled = $false` | 标题区不追加 wttr 片段 (只渲染原标题) |
| wttr.in 超时 / 网络失败 / 远端空响应 | 静默返回空串; 主菜单标题渲染不受影响 |
| 模块作用域 wttr 缓存 (`$script:_WttrCache`) 命中 | 零 HTTP; 二次开菜单直接命中 |

> `Get-WttrWeather` 的容错语义统一收敛在该函数里: HTTP 失败一律返回 `""` + `Write-Verbose` 诊断, **绝不抛异常污染菜单**.

---

### 🌤️ 提示符天气

本项目**不接管** `Function:prompt`，prompt 渲染由 starship 接管。

`Get-WttrWeather` 仍保留为私有函数，供用户在自定义 prompt 中自行调用：

```powershell
# 示例: 在 ~/.ShellPrompt/config.ps1 或自己的 profile 中加 prompt wrapper
# PSReadLine 自定义 prompt 可参考 PSReadLine 文档
```

公开命令 `Update-Weather` 用于手动刷新并打印 wttr 短串。

## 🚀 安装

### 前置依赖

| 依赖 | 说明 |
|------|------|
| PowerShell 7.6+ | **唯一支持版本**。`ShellPrompt.psd1` 声明 `PowerShellVersion = '7.6'`；Windows PowerShell 5.1 已不再支持。抬高门槛的原因是交互菜单主轨依赖的 [`PSTui`](Modules/PSTui/1.0.5/README.md) 是 .NET 10 二进制模块, 要求 PS 7.6+ |
| `PSTui` | 交互菜单**唯一**渲染实现, 仓库内置于 `Modules/PSTui/`。缺失/版本冲突/非交互宿主时, 交互菜单调用会抛出可定位的终止错误（模块本身仍可正常加载） |
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
| `DarkGray` | `\e[38;2;50;50;50m` | 深灰（注：`DarkGray` **未**在 `$script:ColorCache` 预热，热路径会触发冷回退） |
| `MidGray` | `\e[38;2;100;100;100m` | 中灰 |
| `LightGray` | `\e[38;2;180;180;180m` | 浅灰 |
| `White` | `\e[38;2;255;255;255m` | 白色 |
| `Cyan` | `\e[38;2;112;199;209m` | 标题色（菜单/标题区主色，提升与正文色的层级差） |
| `Danger` | `\e[38;2;220;90;90m` | 危险项色（删除/不可逆操作提示） |
| `Warning` | `\e[38;2;220;180;80m` | 警告项色（非推荐路径/需二次确认操作） |
| `SelectedBg` | `\e[48;2;112;199;209;30m\e[38;2;20;20;20m` | 选中态反色背景（Cyan 底 + 黑字） |
| `BgDarker` | `\e[48;2;40;40;40m` | 危险项底色（危险项加强高亮，可选） |
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

### 公开命令

| 命令 | 说明 | 关键参数 | 依赖 | 源文件 |
|------|------|----------|------|--------|
| `Show-UserScoopLogo` | 显示 ANSI 欢迎 Banner 及随机语录(委托 `New-WelcomeBanner` + `Get-RandomQuote`,带 mtime 缓存) | `-QuotesPath`、`-ColorPrimary` | — | [`Show-UserScoopLogo.ps1`](ShellPrompt/Public/Show-UserScoopLogo.ps1) |
| `Start-TmuxSession` | 远程 tmux 会话交互式管理(进入后展示欢迎 banner + SSH 探测 / 会话刷新期间 spin 动画 + 超时控制) | `-HostName` | ssh、tmux | [`Start-TmuxSession.ps1`](ShellPrompt/Public/Start-TmuxSession.ps1) |
| `Update-Weather` | 强制刷新 wttr Short 缓存并 `Write-Host` 输出单行天气, 用于手动验证 wttr.in 可达性 | — | curl.exe / `Invoke-RestMethod` | [`Update-Weather.ps1`](ShellPrompt/Public/Update-Weather.ps1) |
| `Copy-SshPublicKey` | 一键推送 SSH 公钥到远程主机 | `-RemoteHost`、`-IdentityFile`、`-Port` | ssh | [`Copy-SshPublicKey.ps1`](ShellPrompt/Public/Copy-SshPublicKey.ps1) |
| `Invoke-Reload` | 一键重载 PowerShell 配置 | — | — | [`Invoke-Reload.ps1`](ShellPrompt/Public/Invoke-Reload.ps1) |

### 内部封装（不通过 `FunctionsToExport` 暴露）

| 函数 | 说明 | 关键参数 | 源文件 |
|------|------|----------|--------|
| `Invoke-WithProgress` | 执行 `-ScriptBlock`,默认路径显示 Spectre 进度动画,轮询路径静默执行(带硬超时);支持 `-PollScript` 完成检测与 `-TimeoutSeconds`,异常统一重拋 | `-ScriptBlock`、`-PollScript`、`-TimeoutSeconds`、`-Style` | [`Invoke-WithProgress.ps1`](ShellPrompt/Private/Invoke-WithProgress.ps1) |

> **P2 UX 流程**(`Start-TmuxSession` 启动后顺序):
> 1. **欢迎 banner** — `New-WelcomeBanner` 渲染主机名 + 随机语录(见 [`New-WelcomeBanner.ps1`](ShellPrompt/Private/New-WelcomeBanner.ps1))
> 2. **SSH 探测 + 会话刷新** — `Invoke-WithProgress` 包覆,默认路径期间显示 Spectre 进度动画;超时默认 60s(见 [`Invoke-WithProgress.ps1`](ShellPrompt/Private/Invoke-WithProgress.ps1))
> 3. **主机 / 会话选择** — `Show-HostSelector` / `Show-SessionManager` 由 GridView 主轨驱动(见 [`Invoke-GridViewMenu.ps1`](ShellPrompt/Private/Invoke-GridViewMenu.ps1))
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
    ├── ShellPrompt.psd1               # 模块清单 (ModuleVersion 2.0.0)
    ├── ShellPrompt.psm1               # 模块入口脚本
    ├── Settings.ScriptAnalyzer.psd1   # PSScriptAnalyzer 规则配置
    ├── CHANGELOG.md
    ├── LICENSE                        # MIT 协议
    ├── Tests/                         # Pester 测试套件 (9 个文件: 8 个 *.Tests.ps1 + 1 个入口)
    │   ├── Get-ConsoleUiBackend.Tests.ps1
    │   ├── Get-TmuxSessions.Tests.ps1
    │   ├── Get-WttrWeather.Tests.ps1
    │   ├── Invoke-Tests.ps1
    │   ├── Set-TgColorScheme.Tests.ps1
    │   ├── ShellPrompt.Tests.ps1
    │   ├── Show-ProgressSpinner.Tests.ps1
    │   ├── Update-Weather.Tests.ps1
    │   └── Write-GridViewHint.Tests.ps1
    ├── Public/                        # 用户面向命令（稳定 API）
    │   ├── Copy-SshPublicKey.ps1
    │   ├── Invoke-Reload.ps1
    │   ├── Show-UserScoopLogo.ps1
    │   ├── Start-TmuxSession.ps1
    │   └── Update-Weather.ps1
    └── Private/                       # 内部辅助函数（不暴露给用户）
        ├── Connect-TmuxSession.ps1        # 附着已有 tmux 会话
        ├── ConvertTo-SshEscapedString.ps1 # SSH 单引号转义
        ├── ConvertTo-TmuxRefreshSelection.ps1 # 「刷新会话列表」选中项契约
        ├── Get-ConsoleUiBackend.ps1       # 菜单主轨可用性检测 (GridView) + Assert-ConsoleUiReady
        ├── Get-GridViewColumnPlan.ps1     # GridView 列可见性与 keyColumn 规划
        ├── Get-GridViewHostRow.ps1        # GridView 主机选择行构造
        ├── Get-GridViewManagerRow.ps1     # GridView 会话管理行构造
        ├── Get-SshArgs.ps1                # SSH 参数生成器
        ├── Get-SshConfigHosts.ps1         # SSH config 主机解析
        ├── Get-TmuxRefreshedSession.ps1   # 刷新时重新拉取会话列表
        ├── Get-TmuxSessionGridRow.ps1     # GridView 会话列表行构造（含刷新行）
        ├── Get-TmuxSessions.ps1           # 远程 tmux 探测与列表
        ├── Get-TmuxSessionStateText.ps1   # 「● 已附着 / ○ 已分离」状态文案
        ├── Get-TmuxSessionSummary.ps1    # 「附 N / 分 M」标题计数
        ├── Get-WttrWeather.ps1            # wttr.in 天气查询 (纯函数, 10 分钟缓存, 供 Update-Weather / 菜单标题区复用)
        ├── Initialize-Config.ps1          # 配置初始化与缓存
        ├── Initialize-GridViewColorScheme.ps1 # GridView 配色初始化（失败仅告警）
        ├── Invoke-GridViewMenu.ps1        # GridView 主轨菜单（主机/会话/会话列表, 在 -Title 区追加单行天气）
        ├── Invoke-SshCaptureOutput.ps1    # SSH 异步输出捕获
        ├── Invoke-SshCommand.ps1          # SSH 命令调度（主线逻辑）
        ├── Invoke-WithProgress.ps1        # 进度封装 (同步 Spectre / 静默轮询)
        ├── New-TmuxSession.ps1            # 创建新 tmux 会话
        ├── New-WelcomeBanner.ps1          # [P2] 欢迎 Banner 纯函数（主机名+随机语录）
        ├── Remove-TmuxSession.ps1         # 删除 tmux 会话
        ├── Reset-TerminalMode.ps1         # 终端编码/TERM 恢复
        ├── Resolve-ColorTable.ps1         # 统一颜色表解析（调用方覆盖 → 缓存 → 配置层默认值）
        ├── Restore-GridViewSelection.ps1  # GridView 选中项归一化与隐藏字段恢复
        ├── Save-OriginalTerminalState.ps1 # 终端状态保存
        ├── Set-TgColorScheme.ps1          # Terminal.Gui Scheme 配色
        ├── Show-HostSelector.ps1          # 主机选择菜单（分发器, 固定 GridView 主轨）
        ├── Show-ProgressSpinner.ps1       # 加载动画 (当前无生产调用方, 仅测试覆盖)
        ├── Show-SessionManager.ps1        # 会话管理菜单（分发器, 固定 GridView 主轨）
        ├── Show-TmuxSessionList.ps1       # 会话列表（含「刷新」原地重绘循环)
        ├── Test-SshHostName.ps1           # 主机名校验
        ├── Write-TmuxAvailabilityNotice.ps1 # 远程 tmux 探测结果提示
        └── Write-TmuxWelcomeBanner.ps1    # tmux 会话管理器欢迎 banner
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
│   · 入口文件(只登记 3 个,不再手工列举依赖): │
│     ① Initialize-Config.ps1                 │
│     ② New-WelcomeBanner.ps1                 │
│     ③ Show-UserScoopLogo.ps1                │
│   · 依赖自动补齐:                          │
│     扫描 Private/Public 的函数定义建立索引, │
│     用 AST 提取真实命令调用, 解析出依赖闭包 │
│     并按依赖顺序(被依赖者在前)dot-source      │
│     (例: Resolve-ColorTable 自动被补齐)      │
│   · 启动图缓存 (2026-10-18 起):             │
│     依赖闭包结果缓存到用户缓存目录的 JSON,   │
│     下次启动校验所有参与文件的                │
│     (mtime, 长度) 未变即命中缓存,            │
│     跳过索引 + AST 解析(约 130ms)            │
│   · 自检: 欢迎语链路命令缺失时 Write-Warning │
│   · 显示欢迎 Banner (委托 New-WelcomeBanner │
│     + Get-RandomQuote,带 mtime 缓存)        │
│   · 设置 ll / which 别名                    │
└─────────────────────────────────────────────┘
     │
     ▼
┌─────────────────────────────────────────────┐
│ ③ Profile Phase 2 (延迟初始化)              │
│   · Fnm (Node.js) — 走缓存                  │
│   · Starship Prompt — 同步 init             │
│   · PSReadLine                              │
└─────────────────────────────────────────────┘
     │
     ▼
┌─────────────────────────────────────────────┐
│ ④ Profile Phase 3 (重载计时)               │
│   · Stopwatch 停止                          │
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
│   · 主轨可用性检测为惰性执行(不在加载期跑)  │
└─────────────────────────────────────────────┘
```

### 关注点分离

- [`Microsoft.PowerShell_profile.ps1`](Microsoft.PowerShell_profile.ps1) — **仅处理**模块加载、环境初始化与启动配置。**不得包含**复杂业务逻辑。
- [`Public/`](ShellPrompt/Public/) — 用户面向命令，保持稳定 API 行为，包含 `.SYNOPSIS` 等帮助注释。
- [`Private/`](ShellPrompt/Private/) — 内部辅助函数，**不得暴露**给用户。

### v2.0 Spinner/Progress 单轨 Spectre 调度

spinner 与 ScriptBlock 进度动画在 v2.0 起改为 **单轨 Spectre.Console 架构**。模块清单声明 `PowerShellVersion = '7.6'`，`PwshSpectreConsole` 是**硬依赖**（缺失即 `ShellPrompt.psm1` 抛终止错误，不做静默降级）。

> **重要区分**: 进度动画是**单轨 Spectre**, 交互菜单是**单轨 GridView (PSTui)**, 见下文「交互菜单后端 (PSTui GridView 单轨)」。Spectre.Console **不负责菜单渲染**, 只负责 spinner、进度动画以及菜单上方的提示行/删除确认。

| 路径 | 渲染后端 | 触发条件 | 存在原因 |
|------|----------|----------|----------|
| **同步封装** | `Invoke-SpectreCommandWithStatus` | 默认 | Spectre 完整动画生命周期 |
| **轮询封装** | 静默轮询（不绘制动画）+ 结束后返回状态对象（`Result` / `Frames` / `Status` / `ElapsedMs`） | `-PollScript` / `-SuppressConsole` / 显式 `<60` 的 `-TimeoutSeconds` | Spectre API 无 poll / 无硬超时 / 无法抑制控制台 |

`Show-ProgressSpinner` 已废弃 `-ForceLegacy` 参数与 `Test-SpectreSpinnerAvailable` 探测函数；`-ForceLegacy` 不再是有效参数。v2.1 起轮询封装不再自绘 spinner，因此 `Show-ProgressSpinner` 当前没有生产调用方（仅测试覆盖），只保留 `Get-SpinnerStyleMapping` 供 `Invoke-WithProgress` 使用。

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

## 🎛️ 交互菜单后端（PSTui GridView 单轨）

`sss`（[`Start-TmuxSession`](ShellPrompt/Public/Start-TmuxSession.ps1)）里的「主机选择」和「会话管理」两个交互菜单是**单轨**的：唯一渲染实现是 [`Modules/PSTui`](Modules/PSTui/1.0.5/README.md) 的 `Out-ConsoleGridView` 表格视图（[`Invoke-GridViewMenu.ps1`](ShellPrompt/Private/Invoke-GridViewMenu.ps1)）。自研 ANSI 降级轨（`AnsiFallback`）已于 2026-10-18 整体移除。

主轨可用性检测由 [`Get-ConsoleUiBackend`](ShellPrompt/Private/Get-ConsoleUiBackend.ps1) 提供（`PSTui` 可发现性 / 同名命令冲突 / `Terminal.Gui` 主版本争用 / 交互式宿主），其中 `Backend` **恒为** `'GridView'`。

**检测是惰性的（2026-10-18 起）**：模块加载期**不再**执行检测（实测该项是模块导入阶段的最大单一热点，约 500ms，且启动期根本用不到），改为首次真正需要时（`Get-ConsoleUiState` / `Assert-ConsoleUiReady`）现场检测一次，结果缓存到 `$script:ConsoleUiBackend`，后续复用。

| 调用 | 时机 | 耗时 |
|------|------|------|
| 模块加载 | 不检测，`$script:ConsoleUiBackend` 保持 `$null` | 0ms |
| 首次 `Get-ConsoleUiState` | 现场检测并缓存 | 约 360ms（一次性） |
| 后续调用 | 复用缓存 | 约 0–1ms |

| 检测项 | 判定 |
|------|------|
| `PSTui` 可发现 | 模块必须已安装（仓库内置 `Modules/PSTui/`） |
| 无同名命令冲突 | 环境中不得存在其它 `Out-ConsoleGridView` 来源 |
| `Terminal.Gui` 主版本为 2 | 避免与其它 Terminal.Gui 主版本争用 |
| 交互式宿主 | stdin 未被重定向（管道 / CI / 输入重定向场景不满足） |

**Starship 同步 init（2026-10-18 起回退到 P3 优化前）**：profile 阶段 2 `Invoke-DeferredInit` 同步执行 `starship init powershell --print-full-init`，starship 自身替换 `Function:prompt` 完成接管; `Initialize-StarshipLazy` 与 `Register-WttrPromptWrapper` 全链路已随方案 B 部分回退一并移除（详见 `CHANGELOG.md` `[Unreleased] / Removed`）。

**fnm env 走缓存路径（2026-10-18 起）**：`fnm env --use-on-cd --shell powershell` 子进程 (实测 ~88~124ms) 改为走 `Initialize-FnmEnvironment` 缓存路径. 缓存键 = `fnm|<exe mtime ticks>|<exe length>|powershell|ns=<node version list>` (fnm 可执行文件变化 / `fnm install` / `fnm uninstall` 自动失效), 缓存文件 `$env:LOCALAPPDATA\ShellPrompt\fnm-env.json`. **PATH 永不缓存**(避免静默覆盖用户临时 PATH 修改); 运行时基于**当前** `$env:PATH` 重算 fnm 注入路径. 失败保底走 `Set-FnmEnvironmentByFallback` 直接跑 `fnm env` 子进程 —— 正确性优先于速度.

**主轨不可用时不再静默降级**：分发器在调用实现前统一执行 `Assert-ConsoleUiReady -Feature <功能名>`，抛出**可定位的终止错误**（含功能名与具体原因），例如：

```
[ShellPrompt] tmux 会话列表菜单 需要控制台 UI 主轨 (PSTui GridView), 但当前环境不可用: ...
```

模块**加载本身**不会因此失败（检测异常时 `Get-ConsoleUiState` 兜底返回 `Available=$false` 的可诊断对象，只 `Write-Verbose` 记录，**不向 stderr 写入任何噪声**），只有真正调用交互菜单时才抛错。

### 对外契约

[`Show-HostSelector`](ShellPrompt/Private/Show-HostSelector.ps1) / [`Show-SessionManager`](ShellPrompt/Private/Show-SessionManager.ps1) / [`Show-TmuxSessionList`](ShellPrompt/Private/Show-TmuxSessionList.ps1) 是纯分发器，返回 `PSCustomObject`（`.Value` 为选中值，`$null` 表示用户取消）。调用方无需感知渲染实现细节。

### 会话管理菜单文案（Desc）

会话管理菜单的**说明列（Desc）**为精简后的短文案；命令名、`Action` 键与「选中 → 动作」映射不受影响。

| Action | Label | Desc |
|--------|-------|------|
| `Attach` | 附着/恢复 tmux 会话 | `附到 tmux 会话` |
| `New` | 创建新 tmux 会话 | `创建 tmux 会话` |
| `Remove` | 删除 tmux 会话 | `删除 tmux 会话` |
| `Ssh` | 直接 SSH 登录 | `直接 SSH 登录` |
| `Refresh` | 刷新会话列表 | `刷新会话` |

> 菜单实现见 [`Invoke-GridViewMenu.ps1`](ShellPrompt/Private/Invoke-GridViewMenu.ps1)。修改文案时在该文件内调整。

### 会话列表的「已附着 / 已分离」状态

`sss` 的会话列表会为每个 tmux 会话显示一个 **State** 状态列，用于区分该会话当前是否被终端附着：

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

| 刷新入口 | 表现 |
|---------|------|
| 表格最后一行 `⟳ 刷新会话列表` | 选中后**原地重绘**整张表，仍停留在会话列表 |

刷新语义：

- **仅由用户手动触发**。菜单打开期间**没有任何定时器 / 后台轮询**，不占用额外进程或线程，也不会在后台悄悄刷新。
- 刷新会**重新执行一次 `tmux` 查询**，拿到最新的附着状态与窗口数，并据此重算「附 N / 分 M」。
- 刷新是**原地重绘**，不会退出菜单、不会回到上一级菜单、不需要重新输入主机名。
- 刷新后若已经没有可用会话，会给出告警并返回上一层（等价于「无可选会话」）。
- **对外契约不变**：仍返回带 `.Value` 的 `PSCustomObject` 或 `$null`；刷新项通过独立的刷新标记（`.IsRefresh` / 内部哨兵值）区分，不会与真实会话名混淆。

典型使用场景：

- 你在另一个终端标签页 `tmux attach` 了某个会话 → 回到本终端打开会话列表 → 选 `⟳ 刷新会话列表` → State 列与「附 N / 分 M」立即更新。
- 刚用 `tmux kill-session` 删掉了会话，但列表还显示旧记录 → 刷新一次即可看到最新结果。
- 在列表里误选了某行并进入会话 → 退出后重新打开列表即取新快照，无需手动刷新。

### 查看主轨检测结果（调试用）

```powershell
# 查看当前主轨可用性检测结果（Backend 恒为 'GridView'）
# 注意: 惰性检测, 首次调用会现场跑一次检测并缓存结果
& (Get-Module ShellPrompt) { Get-ConsoleUiState | Format-List }
```

> 交互菜单不再提供 `-Backend` 参数，也不存在 `UI.Backend` 配置项。旧配置文件中的 `UI.Backend = 'AnsiFallback'` 将**被忽略**（不报错），主轨不可用时直接抛终止错误。

### 配置项（`$HOME/.ShellPrompt/config.ps1`）

| 键 | 默认 | 说明 |
|----|------|------|
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
`Focus` | `137,209,133` / `40,40,40` | **聚焦列头 + 表格有焦点时的选中行**（亮绿字 + 稍亮底） |
`HotFocus` | `20,20,20` / `130,215,220` | 其它 View 的聚焦热区（TableView 不读取） |
`Active` | `137,209,133` / `40,40,40` | **焦点不在表格时的选中行**（同 `Focus`） |
`HotActive` | `20,20,20` / `130,215,220` | 激活项热区（TableView 不读取） |
`Highlight` | `137,209,133` / `40,40,40` | 高亮标记（鼠标热区，与 `Focus` / `Active` 同色） |
`Editable` | `137,209,133` / `20,20,20` | 可编辑区（过滤框，亮绿字 + 近黑底） |
`ReadOnly` | `159,177,159` / `30,30,30` | 只读行 |
`Disabled` | `100,100,100` / `30,30,30` | 禁用行 |

**迁移说明（绿主题列头配色，2026-10-18 起）**：TG 2.4.10 的 `TableView.RenderRow` 用 `hasFocus ? scheme.Focus : scheme.Active` 决定选中行取色，而 `RenderHeaderMidline` 用 `scheme.Focus` 画聚焦列头——`Focus` 被**列头与选中行共用**。v2.1 把 `Focus` / `Active` 设为同色（Cyan 底 + 近黑字）以统一高亮，但带来"列头青色 + 正文绿字"的视觉割裂。本轮调整（2026-10-18）把 `Focus` / `Active` / `Highlight` 改为**亮绿字 (`137,209,133`) + 稍亮底 (`40,40,40`)**，`Editable` 改为**亮绿字 + 近黑底 (`20,20,20`)**：
- **两种焦点状态下的选中行高亮一致**（保留 v2.1 的不变量）；
- **列头与正文同为绿字**，与绿主题统一；
- **过滤框可读**：`Editable` 槽位为亮绿字配近黑底，对比度高，输入文字始终清晰。

> 只想自定义高亮色：改 `UI.Theme.Slots` 里的 `Focus` / `Active` / `Highlight`（三者保持完全相同），可任选底色。未知或不可写的槽位名会被静默跳过，不会报错。

### 能力说明（GridView 主轨的限制与补偿）

| 能力项 | GridView 主轨现状 | 补偿手段 |
|---|---|---|
| 行级红色 / 危险项高亮 | PSTui 未开放 Color/Theme API | `State` 列文本（`⚠ 危险` / `⚠ 备选` / `● last`） |
| 底部帮助文本行 | 表格视图无底部帮助区 | 菜单**上方**一行 Spectre 提示（`↑↓ 选择  Enter 确认  Esc 退出`） |
| 实时增量过滤 | 无键盘级过滤回调 | `-Focus Filter` 表格筛选框（`UI.GridViewFocus = 'Filter'`） |
| `Disabled` 行灰显 | 不支持渲染禁用态 | `State` 列标注 + 选中后**阻断**并提示 |
| 独立「退出」行 | 表格不再放 Exit 行 | `Esc` / `Ctrl-C` 退出，返回 `$null` |

### 性能特征（GridView 主轨）

| 维度 | `GridView` 主轨 |
|---|---|
| 渲染方式 | PSTui `Out-ConsoleGridView` 表格视图, 宿主内一次性重绘 |
| 每次按键重绘量 | 整表重绘, 由 TG 内部批处理 |
| 整屏清屏 | 无此机制 |
| 非 TTY / stdout 重定向 | 主轨不可用, 交互菜单调用直接抛终止错误 (不再降级到其它渲染实现) |
| 单个菜单项渲染耗时 | 不适用 (表格单元格) |

**结论**: 「ui 卡顿」问题已消解 —— 三个交互菜单**全部且仅**走 `GridView` 主轨, 逐行绝对定位覆盖的自研 ANSI 渲染实现已随降级轨一并移除, 相关的手写清屏、颜色表补全与三区布局代码均不再存在。

> 真实交互终端的手感无法在自动化环境量化 (stdin 被重定向), 需人工按 [`docs/UI-Refactor-Plan.md` 附录 C.7](docs/UI-Refactor-Plan.md) 的验收清单确认。

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
> | **例外**: UI 渲染 | `Write-Host` 允许 | `Show-UserScoopLogo` |

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
| Profile 启动报 `Get-RandomQuote` / `New-WelcomeBanner` / `Resolve-ColorTable` 未识别 | `Microsoft.PowerShell_profile.ps1` Phase 1 依赖未就绪 | Phase 1 已改为**自动解析依赖闭包**，正常情况下无需手工干预；若仍出现，请查看 Phase 1 自检输出的 `缺失命令` / `缺失文件` 列表，并确认对应文件是否被误删或改名 |
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
