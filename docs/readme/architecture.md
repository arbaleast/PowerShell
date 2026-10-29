# 🏗️ 架构

## 目录结构

```
PowerShell/
├── .github/                          # CI: Pester 套件 + PSScriptAnalyzer
│   └── workflows/test.yml
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
│   │   ├── commit-convention.md       # 提交信息规范
│   │   ├── environment.md             # 本机 pwsh 安装位置与兜底查询
│   │   └── wttr.md                    # 菜单标题区天气约束
│   ├── readme/                        # 用户手册分片（从 README 拆出, 一章一文件）
│   │   ├── architecture.md / commands.md / configuration.md
│   │   ├── features.md / gridview-menus.md / development.md
└── ShellPrompt/                       # 模块根目录
    ├── ShellPrompt.psd1               # 模块清单 (ModuleVersion 2.0.0)
    ├── ShellPrompt.psm1               # 模块入口脚本
    ├── Settings.ScriptAnalyzer.psd1   # PSScriptAnalyzer 规则配置
    ├── CHANGELOG.md
    ├── LICENSE                        # MIT 协议
    ├── Tests/                         # Pester 测试套件 (14 个文件: 13 个 *.Tests.ps1 + 1 个入口, 2026-10-29 核对)
    │   ├── Format-GridViewStateText.Tests.ps1
    │   ├── Get-ConsoleUiBackend.Tests.ps1
    │   ├── Get-SpinnerStyleMapping.Tests.ps1
    │   ├── Get-TmuxSessions.Tests.ps1
    │   ├── Get-WttrTitleSuffix.Tests.ps1
    │   ├── Get-WttrWeather.Tests.ps1
    │   ├── Get-WttrWeatherDescMap.Tests.ps1
    │   ├── Initialize-Config.Tests.ps1
    │   ├── Invoke-Tests.ps1
    │   ├── Invoke-WithProgress.Tests.ps1
    │   ├── Set-TgColorScheme.Tests.ps1
    │   ├── ShellPrompt.Tests.ps1
    │   ├── Tmux-ExitCode.Tests.ps1
    │   └── Update-Weather.Tests.ps1
    ├── Public/                        # 用户面向命令（稳定 API）
    │   ├── Copy-SshPublicKey.ps1
    │   ├── Invoke-Reload.ps1
    │   ├── Show-UserScoopLogo.ps1
    │   ├── Start-TmuxSession.ps1
    │   └── Update-Weather.ps1
    └── Private/                       # 内部辅助函数（不暴露给用户, 共 41 个 .ps1, 2026-10-29 核对）
        ├── Connect-TmuxSession.ps1        # 附着已有 tmux 会话
        ├── ConvertTo-SshEscapedString.ps1 # SSH 单引号转义
        ├── ConvertTo-TmuxRefreshSelection.ps1 # 「刷新会话列表」选中项契约
        ├── Format-GridViewStateText.ps1   # State 列文本 + 危险/备选颜色接驳
        ├── Get-ConsoleUiBackend.ps1       # 菜单主轨可用性检测 (GridView) + Assert-ConsoleUiReady
        ├── Get-GridViewColumnPlan.ps1     # GridView 列可见性与 keyColumn 规划
        ├── Get-GridViewHostRow.ps1        # GridView 主机选择行构造
        ├── Get-GridViewManagerRow.ps1     # GridView 会话管理行构造
        ├── Get-HostSelectorStateText.ps1  # 主机选择行状态文案（如 ★ 最近）
        ├── Get-SpinnerStyleMapping.ps1   # ShellPrompt 样式名 → Spectre.Spinner.Known 成员名
        ├── Get-SshArgs.ps1                # SSH 参数生成器
        ├── Get-SshConfigHosts.ps1         # SSH config 主机解析
        ├── Get-TmuxRefreshedSession.ps1   # 刷新时重新拉取会话列表
        ├── Get-TmuxSessionGridRow.ps1     # GridView 会话列表行构造（含刷新行）
        ├── Get-TmuxSessions.ps1           # 远程 tmux 探测与列表
        ├── Get-TmuxSessionStateText.ps1   # 「● 已附着 / ○ 已分离」状态文案
        ├── Get-TmuxSessionSummary.ps1    # 「附 N / 分 M」标题计数
        ├── Get-WttrTitleSuffix.ps1        # 菜单标题区 wttr 后缀拼装 (j1 端点 + 中文映射)
        ├── Get-WttrWeather.ps1            # wttr.in 天气查询 (纯函数, 10 分钟缓存, 供 Update-Weather / 菜单标题区复用)
        ├── Get-WttrWeatherDescMap.ps1     # wttr 天气描述 → 中文内置字典 (42 条)
        ├── Initialize-Config.ps1          # 配置初始化与缓存
        ├── Initialize-FnmEnvironment.ps1  # fnm 环境缓存初始化 (fnm-env.json)
        ├── Initialize-GridViewColorScheme.ps1 # GridView 配色初始化（失败仅告警）
        ├── Invoke-GridViewMenu.ps1        # GridView 主轨菜单（主机/会话/会话列表, 在 -Title 区追加单行天气）
        ├── Invoke-SshCaptureOutput.ps1    # SSH 异步输出捕获
        ├── Invoke-SshCommand.ps1          # SSH 命令调度（主线逻辑）
        ├── Invoke-WithProgress.ps1        # 进度封装 (Spectre 单轨)
        ├── New-TmuxSession.ps1            # 创建新 tmux 会话
        ├── New-WelcomeBanner.ps1          # [P2] 欢迎 Banner 纯函数（主机名+随机语录）
        ├── Remove-TmuxSession.ps1         # 删除 tmux 会话
        ├── Reset-TerminalMode.ps1         # 终端编码/TERM 恢复
        ├── Resolve-ColorTable.ps1         # 统一颜色表解析（调用方覆盖 → 缓存 → 配置层默认值）
        ├── Restore-GridViewSelection.ps1  # GridView 选中项归一化与隐藏字段恢复
        ├── Save-OriginalTerminalState.ps1 # 终端状态保存
        ├── Set-TgColorScheme.ps1          # Terminal.Gui Scheme 配色
        ├── Show-HostSelector.ps1          # 主机选择菜单（分发器, 固定 GridView 主轨）
        ├── Show-SessionManager.ps1        # 会话管理菜单（分发器, 固定 GridView 主轨）
        ├── Show-TmuxSessionList.ps1       # 会话列表（含「刷新」原地重绘循环)
        ├── Test-SshHostName.ps1           # 主机名校验
        ├── Write-TmuxAvailabilityNotice.ps1 # 远程 tmux 探测结果提示
        └── Write-TmuxWelcomeBanner.ps1    # tmux 会话管理器欢迎 banner
```

## 加载流程

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
│ ② Profile Phase 1                           │
│   · 显式有序清单(5 个文件,被依赖者在前):     │
│     ① Initialize-Config.ps1                 │
│       (定义 Get-CachedConfig)                │
│     ② Resolve-ColorTable.ps1                │
│       (依赖 Get-CachedConfig)                │
│     ③ New-WelcomeBanner.ps1                 │
│       (依赖 Resolve-ColorTable)              │
│     ④ Initialize-FnmEnvironment.ps1         │
│       (自包含)                               │
│     ⑤ Show-UserScoopLogo.ps1                │
│       (依赖 Get-CachedConfig /               │
│        Get-RandomQuote / New-WelcomeBanner)  │
│   · 加载 ~/.ShellPrompt/config.ps1 用户配置  │
│     (在 Initialize-Config.ps1 内,先于预热缓存)│
│   · 自检: 用 AST 取这 5 个文件里真实调用的   │
│     命令名逐个检查可见性; 缺失时             │
│     Write-Warning 报出缺哪个文件的哪个命令   │
│   · 显示欢迎 Banner (委托 New-WelcomeBanner  │
│     + Get-RandomQuote,带 mtime 缓存)         │
│   · 设置 ll / which 别名                     │
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
│   · 把仓库 Modules/ 注入 PSModulePath       │
│   · Import-Module PwshSpectreConsole (硬依赖,│
│     失败即 throw)                            │
│   · dot-source Private/*.ps1 (先), 再 Public│
│   · 用户配置 config.ps1 由 Initialize-Config │
│     加载(Phase 1 与模块各一次)               │
│   · 主轨可用性检测为惰性执行(不在加载期跑)  │
└─────────────────────────────────────────────┘
```

## 关注点分离

- [`Microsoft.PowerShell_profile.ps1`](../../Microsoft.PowerShell_profile.ps1) — **仅处理**模块加载、环境初始化与启动配置。**不得包含**复杂业务逻辑。
- [`Public/`](../../ShellPrompt/Public/) — 用户面向命令，保持稳定 API 行为，包含 `.SYNOPSIS` 等帮助注释。
- [`Private/`](../../ShellPrompt/Private/) — 内部辅助函数，**不得暴露**给用户。

## v2.0 Spinner/Progress 单轨 Spectre 调度

spinner 与 ScriptBlock 进度动画在 v2.0 起改为 **单轨 Spectre.Console 架构**。模块清单声明 `PowerShellVersion = '7.6'`，`PwshSpectreConsole` 是**硬依赖**（缺失即 `ShellPrompt.psm1` 抛终止错误，不做静默降级）。

> **重要区分**: 进度动画是**单轨 Spectre**, 交互菜单是**单轨 GridView (PSTui)**, 见 [交互菜单后端](gridview-menus.md)。Spectre.Console **不负责菜单渲染**, 只负责 spinner、进度动画与删除会话的二次确认(`Read-SpectreConfirm`); 菜单按键提示行已于 2026-10-19 撤回(`Write-GridViewHint` 已于 2026-10-29 删除), 按键说明由 PSTui 自带状态栏提供。

| 路径 | 渲染后端 | 触发条件 | 存在原因 |
|------|----------|----------|----------|
| **同步封装** | `Invoke-SpectreCommandWithStatus` | 唯一路径 | Spectre 完整动画生命周期 |

**2026-10-29 精简**：原先并列的「轮询封装」（`Invoke-WithProgressPolling`，静默轮询 + 硬超时 + 结构化返回）已整体删除。依据：三个生产调用点（`Start-TmuxSession.ps1` 的"加载主机列表" / "检测远程 tmux" / "获取远程 tmux 会话"）全部只传 `-Message` + `-ScriptBlock`，从未进入过轮询分支，轮询分支唯一的消费者是它自己的单元测试。Spectre.Console 的 `Start-AnsiConsoleStatus` 本身没有 timeout 概念，轮询分支宣称的"硬超时"从未在生产链路上生效过。随之删除的 `-PollScript` / `-IntervalMs` / `-TimeoutSeconds` / `-SuppressConsole` / `-SuccessMessage` / `-FailureMessage` 六个参数也不再存在。

同批删除的还有 `Private/Show-ProgressSpinner.ps1`（自绘 spinner，`Get-SpinnerFrame` / `Get-SpinnerSequence` / `ConvertTo-SpectrePlainText` 均无生产调用方）；其中仍被 `Invoke-WithProgress` 使用的 `Get-SpinnerStyleMapping` 已独立成 [`Private/Get-SpinnerStyleMapping.ps1`](../../ShellPrompt/Private/Get-SpinnerStyleMapping.ps1)。

**Spectre markup 转义**：唯一走 `Write-SpectreHost` 的自绘渲染路径已随 `Show-ProgressSpinner` 删除。现存两处 Spectre 输出（`Invoke-SpectreCommandWithStatus` 的标题、`Read-SpectreConfirm` 的提示）都不含裸 `[`，或在调用侧自行转义（见 `Remove-TmuxSession.ps1` 的 `$sessionName.Replace('[', '[[')`）。

**风格映射表** (调用方 `-Style` → Spectre.Spinner.Known)：

| ShellPrompt 样式 | Spectre 内置 | 说明 |
|------------------|--------------|------|
| `Dots` | `Dots6` | 6 点脉冲 (用户原始诉求) |
| `Braille` | `Dots3` | 盲文点阵最接近的 Spectre 等价物 |
| `Ascii` | `Ascii` | 1:1 |
| `Blocks` | `Material` | 竖条高度波浪动画 (Spectre 无 `Block`/`Blocks` 成员名) |
| `Arrows` | `Arrow` | 1:1 |
| 其它 / 未传 | `Dots6` | 安全回退 |

> **`Blocks` 映射修正（2026-10-29）**：原映射到 `Block1`，但 Spectre.Console 的 `Spinner.Known` 成员名里既没有 `Block1` 也没有 `Blocks`，而 `Invoke-SpectreCommandWithStatus -Spinner` 带 `[ValidateSet([SpectreConsoleSpinner])]`，传入不存在的成员名会在**参数绑定阶段**直接抛 `Value 'Block1' is invalid`。已改为视觉等价的 `Material`；回归测试见 [`Tests/Get-SpinnerStyleMapping.Tests.ps1`](../../ShellPrompt/Tests/Get-SpinnerStyleMapping.Tests.ps1)。

**已知约束**：`Invoke-SpectreCommandWithStatus` 底层 `Start-AnsiConsoleStatus` 无硬超时，本封装也不再提供 `-TimeoutSeconds`。调用方需要超时保护时，请在调用外层用 `Stopwatch` 自己包；SSH 连接阶段由 `Get-SshArgs -ConnectTimeout`（默认 5s）兜底，远端命令本身无超时。

