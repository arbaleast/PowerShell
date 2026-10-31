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
│   │   ├── features.md / tui-dashboard.md / development.md
└── ShellPrompt/                       # 模块根目录
    ├── ShellPrompt.psd1               # 模块清单 (ModuleVersion 2.0.0)
    ├── ShellPrompt.psm1               # 模块入口脚本
    ├── Settings.ScriptAnalyzer.psd1   # PSScriptAnalyzer 规则配置
    ├── CHANGELOG.md
    ├── LICENSE                        # MIT 协议
    ├── Tests/                         # Pester 测试套件 (38 个条目: 31 个 *.Tests.ps1 + 3 个诊断脚本 + 3 个门禁入口 + 1 个基线, 2026-10-31 核对)
    │   ├── ConvertTo-TmuxTuiViewModel.Tests.ps1
    │   ├── Diag-TguiRender.ps1                     # 诊断脚本: 真机渲染测量
    │   ├── Diag-TguiResize.ps1                     # 诊断脚本: 真机缩放测量
    │   ├── Enter-TmuxAlternateScreen.Tests.ps1
    │   ├── Get-ConsoleUiBackend.Tests.ps1
    │   ├── Get-SpinnerStyleMapping.Tests.ps1
    │   ├── Get-TguiContext.Tests.ps1
    │   ├── Get-TguiTextWidth.Tests.ps1
    │   ├── Get-TmuxActionDefinition.Tests.ps1
    │   ├── Get-TmuxSessionState.Tests.ps1
    │   ├── Get-TmuxSessions.Tests.ps1
    │   ├── Get-WttrTitleSuffix.Tests.ps1
    │   ├── Get-WttrWeather.Tests.ps1
    │   ├── Get-WttrWeatherDescMap.Tests.ps1
    │   ├── Initialize-Config.Tests.ps1
    │   ├── Invoke-Lint.ps1                         # 门禁入口: PSScriptAnalyzer
    │   ├── Invoke-ProfileSmoke.ps1                 # 门禁入口: profile 冒烟
    │   ├── Invoke-SshCaptureOutput.Tests.ps1
    │   ├── Invoke-Tests.ps1                        # 门禁入口: 跑 Pester 套件
    │   ├── Invoke-TmuxAttach.Tests.ps1
    │   ├── Invoke-TmuxSessionDeletion.Tests.ps1
    │   ├── Invoke-WithProgress.Tests.ps1
    │   ├── New-TguiHostSelectorWindow.Tests.ps1
    │   ├── New-TmuxTuiDashboardWindow.Tests.ps1
    │   ├── New-TmuxTuiSessionTable.Tests.ps1
    │   ├── New-TmuxTuiShortcutList.Tests.ps1
    │   ├── Read-TmuxConsoleLine.Tests.ps1
    │   ├── Set-TguiTheme.Tests.ps1
    │   ├── ShellPrompt.Tests.ps1
    │   ├── Show-TmuxTuiDashboard.Tests.ps1
    │   ├── Ssh-HostName-Validation.Tests.ps1
    │   ├── Start-TmuxSession.TuiDispatch.Tests.ps1
    │   ├── Tmux-SessionState.Tests.ps1
    │   ├── Tmux-SshFailure.Tests.ps1
    │   ├── Update-Weather.Tests.ps1
    │   └── pssa-warning-baseline.txt               # PSSA Warning 指纹基线
    └── Private/                       # 内部辅助函数(不暴露给用户, 共 49 个 .ps1, 2026-10-30 核对)
        ├── ConvertTo-SshArgumentLine.ps1      # SSH 命令行参数拼接
        ├── ConvertTo-SshEscapedString.ps1     # SSH 单引号转义
        ├── ConvertTo-TmuxTuiViewModel.ps1     # 仪表盘视图模型(状态区 + 表格数据)
        ├── Enter-TmuxAlternateScreen.ps1      # 进入备用屏(TGUI 持有终端时静音)
        ├── Get-ConsoleUiBackend.ps1           # Terminal.Gui v2 ALC 就绪检测(Backend 恒 'TerminalGui') + Assert-ConsoleUiReady
        ├── Get-HostSelectorRow.ps1            # 主机选择行构造(LastHost 置顶 + State 标注)
        ├── Get-HostSelectorStateText.ps1      # 主机选择行状态文案(如 ★ 最近)
        ├── Get-SpinnerStyleMapping.ps1        # ShellPrompt 样式名 → Spectre.Spinner.Known 成员名
        ├── Get-SshArgs.ps1                    # SSH 参数生成器
        ├── Get-SshConfigHosts.ps1             # SSH config 主机解析
        ├── Get-TguiContext.ps1                # Terminal.Gui v2 独立 ALC 加载器(vendored DLL)
        ├── Get-TguiTerminalSize.ps1           # 仪表盘布局用的终端尺寸解析(事件报数 > 终端自身 > TG Screen > 缺省)
        ├── Get-TguiTextWidth.ps1              # 终端显示宽度测量(全角计 2, 零宽计 0; 底栏宽度预算用)
        ├── Get-TmuxActionDefinition.ps1       # 仪表盘动作定义(键位/文案/动作值唯一事实源)
        ├── Get-TmuxSessionState.ps1           # 会话可用性与状态判定(Available/Error/ExitCode)
        ├── Get-TmuxSessions.ps1               # 远程 tmux 探测与列表
        ├── Get-WttrTitleSuffix.ps1            # TGUI 标题行 wttr 后缀拼装 (j1 端点 + 中文映射)
        ├── Get-WttrWeather.ps1                # wttr.in 天气查询 (纯函数, 10 分钟缓存)
        ├── Get-WttrWeatherDescMap.ps1         # wttr 天气描述 → 中文内置字典 (42 条)
        ├── Initialize-Config.ps1              # 配置初始化与缓存
        ├── Initialize-FnmEnvironment.ps1      # fnm 环境缓存初始化 (fnm-env.json)
        ├── Invoke-SshCaptureOutput.ps1        # SSH 异步输出捕获
        ├── Invoke-SshCommand.ps1              # SSH 命令调度(主线逻辑)
        ├── Invoke-TguiHostSelector.ps1        # 主机选择器 TGUI 编排(过滤 → 组装 → Init → Run → Shutdown)
        ├── Invoke-TmuxAttach.ps1              # tmux 会话附着/恢复执行
        ├── Invoke-TmuxSessionDeletion.ps1     # 删除 tmux 会话的唯一屏障(二次确认 + kill-session)
        ├── Invoke-TmuxSessionFetch.ps1        # 后台取数(远程 tmux 探测与会话列表)
        ├── Invoke-TmuxTuiAction.ps1           # 仪表盘业务动作分发
        ├── Invoke-WithProgress.ps1            # 进度封装 (Spectre 单轨)
        ├── New-TguiHostSelectorWindow.ps1     # 主机选择器整窗组装(标题/搜索框/主机表/提示行, 无头可测)
        ├── New-TmuxSession.ps1                # 创建新 tmux 会话
        ├── New-TmuxTuiColumnPlan.ps1          # 仪表盘表格列裁剪计划
        ├── New-TmuxTuiDashboardWindow.ps1     # 仪表盘窗口(表格 + 快捷键栏)构造
        ├── New-TmuxTuiLayoutPlan.ps1          # 仪表盘布局计划(零重叠零空档)
        ├── New-TmuxTuiSessionTable.ps1        # 仪表盘会话表 (TableView) 构造
        ├── New-TmuxTuiShortcutList.ps1        # 仪表盘快捷键栏 (Shortcut) 构造
        ├── New-WelcomeBanner.ps1              # [P2] 欢迎 Banner 纯函数(主机名 + 随机语录)
        ├── Read-TmuxConsoleLine.ps1           # 控制台单行读取(带超时)
        ├── Receive-TmuxBackgroundTask.ps1     # 后台取数任务结果回收
        ├── Reset-TerminalMode.ps1             # 终端编码/TERM 恢复
        ├── Resolve-ColorTable.ps1             # 统一颜色表解析(调用方覆盖 → 缓存 → 配置层默认值)
        ├── Resolve-TguiThemeName.ps1          # UI.Theme 名称规范化(未知名回退默认)
        ├── Save-OriginalTerminalState.ps1     # 终端状态保存
        ├── Set-TguiTheme.ps1                  # Terminal.Gui 主题设置 (ALC 原生, 唯一配色路径)
        ├── Show-HostSelector.ps1              # 主机选择菜单(分发器, Terminal.Gui v2 TGUI)
        ├── Show-TmuxTuiDashboard.ps1          # TGUI 仪表盘编排(sss 唯一渲染轨)
        ├── Submit-TmuxBackgroundTask.ps1      # 后台取数任务提交
        ├── Submit-WttrPrefetch.ps1            # 天气预取任务提交
        ├── Test-SshHostName.ps1               # 主机名校验
        ├── Test-TmuxTuiInteractive.ps1        # 交互式终端判定
        └── Write-TmuxWelcomeBanner.ps1        # tmux 会话管理器欢迎 banner
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

> **重要区分**: 进度动画是**单轨 Spectre**, 交互式 UI 是**单轨 Terminal.Gui v2**(vendored `Modules/Terminal.Gui/2.4.10/`, 见 [tmux 管理器 TUI 仪表盘](tui-dashboard.md))。Spectre.Console **不负责交互式 UI 渲染**, 只负责 spinner、进度动画与删除会话的二次确认(`Read-SpectreConfirm`); 历史上挂在菜单上的按键提示行已于 2026-10-19 撤回(`Write-GridViewHint` 已于 2026-10-29 删除), 交互式 UI 的键位说明现由各 TGUI 自带的提示行/快捷键栏承担。

| 路径 | 渲染后端 | 触发条件 | 存在原因 |
|------|----------|----------|----------|
| **同步封装** | `Invoke-SpectreCommandWithStatus` | 唯一路径 | Spectre 完整动画生命周期 |

**2026-10-29 精简**：原先并列的「轮询封装」（`Invoke-WithProgressPolling`，静默轮询 + 硬超时 + 结构化返回）已整体删除。依据：三个生产调用点（`Start-TmuxSession.ps1` 的"加载主机列表" / "检测远程 tmux" / "获取远程 tmux 会话"）全部只传 `-Message` + `-ScriptBlock`，从未进入过轮询分支，轮询分支唯一的消费者是它自己的单元测试。Spectre.Console 的 `Start-AnsiConsoleStatus` 本身没有 timeout 概念，轮询分支宣称的"硬超时"从未在生产链路上生效过。随之删除的 `-PollScript` / `-IntervalMs` / `-TimeoutSeconds` / `-SuppressConsole` / `-SuccessMessage` / `-FailureMessage` 六个参数也不再存在。

同批删除的还有 `Private/Show-ProgressSpinner.ps1`（自绘 spinner，`Get-SpinnerFrame` / `Get-SpinnerSequence` / `ConvertTo-SpectrePlainText` 均无生产调用方）；其中仍被 `Invoke-WithProgress` 使用的 `Get-SpinnerStyleMapping` 已独立成 [`Private/Get-SpinnerStyleMapping.ps1`](../../ShellPrompt/Private/Get-SpinnerStyleMapping.ps1)。

**Spectre markup 转义**：唯一走 `Write-SpectreHost` 的自绘渲染路径已随 `Show-ProgressSpinner` 删除。现存两处 Spectre 输出（`Invoke-SpectreCommandWithStatus` 的标题、`Read-SpectreConfirm` 的提示）都不含裸 `[`，或在调用侧自行转义（见 `Invoke-TmuxSessionDeletion.ps1` 的 `$sessionName.Replace('[', '[[')`）。

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

