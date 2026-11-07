# 🏗️ 架构

本页面向想了解 ShellPrompt 目录结构、模块加载顺序与渲染分工的读者。**仓库内部的强制约束与不变量**以 [`docs/agents/architecture.md`](../agents/architecture.md) 为准，本页不重复维护规则原文。

## 目录结构

> 下面的树只列出主要文件；以仓库中的实际目录为准。`Tests/` 下的测试与门禁脚本会随开发增删，数量以目录为准。

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
│   │   └── (架构 / 开发 / 领域 / 测试 / 提交 / 环境 / 天气 —— 见 AGENTS.md 导航表)
│   ├── readme/                        # 用户手册(按主题拆分: architecture / commands / configuration / features / tui-dashboard / development)
│   └── (完整文档清单见 AGENTS.md 与 README.md 的导航表)
└── ShellPrompt/                       # 模块根目录
    ├── ShellPrompt.psd1               # 模块清单 (ModuleVersion 2.0.0)
    ├── ShellPrompt.psm1               # 模块入口脚本
    ├── CoreScripts.psd1               # 核心脚本清单(Private 与 Public 全量; 新增/删除/重命名 .ps1 必须同步, ModuleLoad.Tests.ps1 断言一致性)
    ├── Settings.ScriptAnalyzer.psd1   # PSScriptAnalyzer 规则配置
    ├── CHANGELOG.md
    ├── LICENSE                        # MIT 协议
    ├── Public/                        # 公开命令定义(导出面以 ShellPrompt.psd1 的 FunctionsToExport 为准)
    ├── Tests/                         # Pester 测试套件: 43 个 *.Tests.ps1 + 3 个诊断脚本 + 3 个门禁入口(Invoke-Tests / Invoke-Lint / Invoke-ProfileSmoke) + 1 个 PSSA 基线; 随开发增删, 以目录为准
    │   └── 门禁入口、Warning 基线与测试/文档义务见 docs/agents/testing.md(文件以 ShellPrompt/Tests/ 目录为准)
    └── Private/                       # 内部辅助函数(不暴露给用户); 全量文件以 CoreScripts.psd1 为准, 此处只列主要文件
        ├── Initialize-Config.ps1      # 配置初始化与缓存(默认配置唯一事实源)
        ├── Resolve-ColorTable.ps1     # 统一颜色表解析(调用方覆盖 → 缓存 → 配置层默认值)
        ├── Show-HostSelector.ps1      # 主机选择菜单(分发器: 断言 + 天气后缀 + 归一返回值)
        ├── Show-SshHostDashboard.ps1  # SSH 主机仪表盘分发器(档案 + 活动历史 → 编排层)
        ├── Invoke-SshHostDashboard.ps1 # SSH 主机仪表盘编排(键盘/异步详情/缩放/请求标识)
        ├── New-SshHostDashboardWindow.ps1 # SSH 主机仪表盘整窗组装(标题带/分类栏/列表/详情/底栏)
        ├── New-SshHostListView.ps1    # 主机列表自定义行(每行 6 Label) + 局部刷新原语
        ├── Get-SshHostProfile.ps1     # ~/.ssh/config 结构化档案 + 分类推导(含 Include)
        ├── Get-SshConfigHosts.ps1     # SSH config 主机解析
        ├── Show-TmuxTuiDashboard.ps1  # TGUI 仪表盘编排(sss 唯一渲染轨)
        ├── New-TmuxTuiDashboardWindow.ps1 # 仪表盘窗口(标题带 + 统计行 + 列表 + 驾驶舱 + 快捷键栏)构造
        ├── New-TmuxTuiSessionRowList.ps1 # tmux 会话自定义行列表(每行 5 Label) + 局部刷新原语
        ├── New-TmuxTuiLayoutPlan.ps1  # 仪表盘布局计划(零重叠零空档)
        ├── New-TmuxTuiShortcutList.ps1 # 仪表盘快捷键栏 (Shortcut) 构造
        ├── Get-TmuxActionDefinition.ps1 # 仪表盘动作定义(键位/文案/动作值唯一事实源)
        ├── Get-TmuxSessions.ps1       # 远程 tmux 探测与列表
        ├── Invoke-TmuxAttach.ps1      # tmux 会话附着/恢复执行
        ├── Invoke-TmuxSessionDeletion.ps1 # 删除 tmux 会话的唯一屏障(二次确认 + kill-session)
        ├── Get-TguiContext.ps1        # Terminal.Gui v2 独立 ALC 加载器(vendored DLL)
        ├── Get-TguiTextWidth.ps1      # 终端显示宽度测量(全角计 2, 零宽计 0; 底栏宽度预算用)
        ├── Set-TguiTheme.ps1          # Terminal.Gui 主题设置 (ALC 原生, 唯一配色路径)
        ├── Set-TguiFrameRate.ps1      # TG 主循环帧率上限(默认 25fps => 40ms 帧周期地板; 抬到 100fps)
        └── New-WelcomeBanner.ps1      # 欢迎 Banner 纯函数(主机名 + 随机语录)
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
│     (五文件清单的强制不变量与依赖理由见       │
│      docs/agents/architecture.md)            │
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

> **重要区分**: 进度动画是**单轨 Spectre**, 交互式 UI 是**单轨 Terminal.Gui v2**(vendored `Modules/Terminal.Gui/2.4.10/`, 见 [TUI 仪表盘](tui-dashboard.md))。Spectre.Console **不负责交互式 UI 渲染**, 只负责 spinner、进度动画与删除会话的二次确认(`Read-SpectreConfirm`)。

`Invoke-WithProgress` 是唯一的进度封装：调用 `Invoke-SpectreCommandWithStatus` 渲染动画，ScriptBlock 抛出的异常原样重抛；不提供 `-TimeoutSeconds` 或轮询参数。**已知约束**：底层 `Start-AnsiConsoleStatus` 无硬超时，需要超时保护时在调用外层用 `Stopwatch` 自己包；SSH 连接阶段由 `Get-SshArgs -ConnectTimeout`（默认 5s）兜底，远端命令本身无超时。

**Spectre markup 转义**：现存的 Spectre 输出都不含裸 `[`，或在调用侧自行转义（见 `Invoke-TmuxSessionDeletion.ps1` 的 `$sessionName.Replace('[', '[[')`）。

**风格映射表** (调用方 `-Style` → Spectre.Spinner.Known) —— 派生自 [`Private/Get-SpinnerStyleMapping.ps1`](../../ShellPrompt/Private/Get-SpinnerStyleMapping.ps1), 回归测试已逐项断言:

| ShellPrompt 样式 | Spectre 内置 | 说明 |
|------------------|--------------|------|
| `Dots` | `Dots6` | 6 点脉冲 (用户原始诉求) |
| `Braille` | `Dots3` | 盲文点阵最接近的 Spectre 等价物 |
| `Ascii` | `Ascii` | 1:1 |
| `Blocks` | `Material` | 竖条高度波浪动画 (Spectre 无 `Block`/`Blocks` 成员名) |
| `Arrows` | `Arrow` | 1:1 |
| 其它 / 未传 | `Dots6` | 安全回退 |

> **`Blocks` 为什么映射到 `Material`**：Spectre.Console 的 `Spinner.Known` 里没有 `Block` / `Blocks` 成员名，而 `Invoke-SpectreCommandWithStatus -Spinner` 带 `[ValidateSet([SpectreConsoleSpinner])]`，传入不存在的成员名会在**参数绑定阶段**直接抛错；`Material` 是视觉等价的竖条动画。回归测试见 [`Tests/Get-SpinnerStyleMapping.Tests.ps1`](../../ShellPrompt/Tests/Get-SpinnerStyleMapping.Tests.ps1)。
