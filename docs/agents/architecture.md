> 本文件由根 [`AGENTS.md`](../../AGENTS.md) 文档导航按需路由加载；通用工作原则与安全边界见根文件。

# 架构与目录规则

## 目录职责

- `Microsoft.PowerShell_profile.ps1`: **MUST ONLY** handle module loading, environment initialization, and startup configuration. **NEVER** put complex business logic here.
- `Public/`: Contains user-facing commands. MUST maintain stable command behavior, use clear PowerShell naming, and include help comments (`.SYNOPSIS`, etc.).
- `Private/`: Contains internal helper functions. **MUST NOT** be exposed to users.
- `ShellPrompt/Settings.ScriptAnalyzer.psd1`: PSScriptAnalyzer configuration. MUST be kept in sync with actual code conventions.

## 兼容性与降级（Compatibility & Fallbacks）

- **支持环境**：PowerShell **7.6+**（唯一支持版本；`ShellPrompt.psd1` 声明 `PowerShellVersion = '7.6'`，抬到 7.6 是因为交互式 UI 依赖的 vendored Terminal.Gui v2 `Modules/Terminal.Gui/<ver>/` 为 .NET 10 二进制）、**Windows**；**不支持** Windows PowerShell 5.1。
  - **当前实现状态（2026-10-29 核对）**：代码是 **Windows-first**，且**只有 Windows 是受支持的平台**。SSH / tmux 主链路硬编码 `ssh.exe`，另有 `$env:LOCALAPPDATA`（fnm env 缓存）、`$env:TEMP`、`$env:USERPROFILE`、`where.exe`、`UserKnownHostsFile=NUL` 等 Windows 专有假设 —— **在 Linux / WSL 上这些路径不可用**（菜单、天气等纯终端功能不受影响）。Linux / WSL 是项目**目标**而非当前支持状态；改造前请先读 [`domain-ssh-tmux.md`](domain-ssh-tmux.md)。
- Prefer feature detection over version checking.
- 模块最低版本由 `ShellPrompt.psd1` 的 `PowerShellVersion` 统一把守, 代码内**不再**做 PS 5.1 分支。
- `PwshSpectreConsole` 是**硬依赖** (不是可选依赖): 加载失败时 `ShellPrompt.psm1` 直接 `throw`, 不做静默降级。
- 交互式 UI 是**单轨制** (2026-10-30 起; 自研 ANSI 降级轨已于 2026-10-18 移除, 原 `Modules/PSTui` `Out-ConsoleGridView` 轨已于 2026-10-30 随整体删除一并移除), 唯一渲染实现是**独立 vendored 的 Terminal.Gui v2** (`Modules/Terminal.Gui/<ver>/`, 版本钉 2.4.10, 经 `Private/Get-TguiContext.ps1` 独立 ALC 加载)。三层分工: **Terminal.Gui v2 = 所有交互式终端 UI; PowerShell = SSH/tmux/配置与业务; ShellPrompt = 命令入口/模块管理/启动初始化**:
  - `Private/Get-ConsoleUiBackend.ps1` 的 `Get-ConsoleUiBackend` 只做 **TerminalGui 就绪判定** (vendored `Modules/Terminal.Gui` 探测 / 交互式终端判定), 其中 `Backend` **恒为** `'TerminalGui'`。
  - **检测是惰性的** (2026-10-18 起): 模块加载期**不执行**检测 (实测是模块导入阶段最大单一热点, 约 500ms, 启动期用不到), 改由 `Get-ConsoleUiState` 在首次真正需要时现场检测一次并缓存到 `$script:ConsoleUiBackend`, 后续复用。
  - 检测自身的实现成本也已优化: vendored 程序集用目录级查找 (`Test-ConsoleUiTguiAssembly`, 取 `Modules/Terminal.Gui/` 下可解析为版本号的最高目录), 交互判定走宿主层信号 (`ConsoleHost` + `RawUI`, `IsInputRedirected` 仅作辅助) —— 两项诊断语义保持不变。
  - **Phase 1 加载清单是显式有序的** (2026-10-29 改): 原先的"函数名 -> 定义文件"静态索引 + AST 依赖闭包 + 拓扑排序 + `$env:LOCALAPPDATA\ShellPrompt\startup-graph.json` 缓存已删除。实际依赖闭包只有 5 个文件 (`Private/Initialize-Config.ps1` → `Private/Resolve-ColorTable.ps1` → `Private/New-WelcomeBanner.ps1`, 另加自包含的 `Private/Initialize-FnmEnvironment.ps1` 与 `Public/Show-UserScoopLogo.ps1`), 用 `$script:StartupLoadOrder` 显式列出即可。**收益**: 启动期不再扫描 Private/Public 全目录、不再向用户目录写 JSON; **代价**: 依赖从"自动推导"变成"手工维护", 由自检兜底 —— 自检用 AST 取出这 5 个文件里真实调用的命令名逐个检查可见性, 缺失时 `Write-Warning` 报出"哪个文件缺哪个命令"。
  - `Show-HostSelector` 是纯分发器, 调用实现前统一执行 `Assert-ConsoleUiReady -Feature <功能名>`。
  - **单轨 (2026-10-30)**: `Start-TmuxSession` 进入 Terminal.Gui v2 仪表盘 (`Private/Show-TmuxTuiDashboard.ps1`) —— 表格内 Enter 选中会话即附着/恢复 (`Private/Invoke-TmuxAttach.ps1` 统一执行), 底栏快捷键覆盖 新建/刷新/SSH/删除/退出。
  - vendored `Modules/Terminal.Gui` 缺失 / stdin 被重定向 → `Assert-ConsoleUiReady` 抛出**可定位的终止错误** (含功能名与原因), **不再静默降级到其它渲染实现**。
  - 调用方 (如 `Start-TmuxSession`) 不感知渲染实现差异, 分发器已无 `-Backend` 参数。

### sss 仪表盘单轨与终端所有权 (2026-10-30 TGUI 迁移)

- `sss` (`Start-TmuxSession`) 的仪表盘**唯一渲染轨**是 Terminal.Gui v2 应用 `Private/Show-TmuxTuiDashboard.ps1`, 布局/表格/键盘/缩放/备用屏全部由 TG 自管; 结构与键位契约见 [`docs/readme/tui-dashboard.md`](../readme/tui-dashboard.md)。SSH 主机选择器同走 Terminal.Gui v2 (`Show-HostSelector` → `Invoke-TguiHostSelector`, 全屏 TGUI); 删除流程走仪表盘当前选中行, 二次确认在业务层。
- **终端所有权不变量**: `$script:TmuxTerminalOwner` 标记当前谁在管终端 ('Legacy' 默认 / 'Tgui' = TG 独占)。
  - 'Tgui' 下 `Enter-TmuxAlternateScreen` / `Exit-TmuxAlternateScreen` / `Clear-TmuxScreen` **整体静音** —— 不发 `\e[?1049h/l`、不做 `[Console]::Clear`、不改 `$script:TmuxAltScreenActive`, 备用屏生命周期由 TG 的 `Init/Run/Shutdown` 独占 (禁止双层嵌套, 契约测试在 `Enter-TmuxAlternateScreen.Tests.ps1` / `Show-TmuxTuiDashboard.Tests.ps1`)。
  - 业务动作 (附着/新建/SSH/删除) 只在 `Run` 已返回 + `Shutdown` 已交还终端之后, 于主屏幕执行。
- 主机选择 (`Show-HostSelector`) **先于**渲染分支: 无 `-HostName` 时先选主机, 取消选择不进任何仪表盘 (`Start-TmuxSession.TuiDispatch.Tests.ps1`)。

### PSTui TableView 留白约束 (P1.7, 2026-10-19 记录; **已存档**)

> PSTui 轨已于 2026-10-30 随 `Modules/PSTui` 删除一并移除, 本节不再是现行行为的约束; 保留为历史裁决记录——其中"禁止对 TG 内部 `TableView.Style` / `ColumnStyle.Width` 作 readonly 字段硬写"的反射红线对现役 TGUI 轨**继续适用**。

- 真机截图观察到的"表格下方大量黑色留白" + 底部状态栏 ("Rows: N | Enter Accept | Esc Close") + 出格式节奏 `Rows.Count < 终端高 - 标题/状态条占用` 的场景下, PSTui `Out-ConsoleGridView` (底层 TG v2 `TableView`) **默认填满分配高度, 不按行数收缩**。
- 调研路径:
  - **改 PSTui 内部 `TableView.Style` 或 `ColumnStyle.Width`** (反射改 readonly 字段): 风险中-高, 依赖 TG IL 行为, 升级即破; 现状决定**不实施**。
  - **弹窗前底部追加状态栏**: 弹窗后 alternate screen buffer 会把 stdout 隔离, 退出后 Spectre 输出会留下, 但同一会话内用户**看不到**, 等于无效; **不实施**。
  - **PromptWrapper / `Restore-GridViewSelection` 限制可见列宽**: PSScriptAnalyzer 已识别的公开层不暴露列宽参数, 改这条路等同于反射, 风险等价; **不实施**。
- 结论: PSTui TableView 的"行少时下方留白"是**上游行为约束**, 不在 `ShellPrompt/` 模块可控范围。任何"修复留白"的尝试都属于本项目边界外, 不进入版本控制。
- 实施纪律: `Private/` 内**禁止**新增/修改对 Terminal.Gui 内部结构的反射代码 (`TableView.Style` / `ColumnStyle.Width` 等 readonly 字段硬写)。如未来 TG 公开层暴露相关参数, 再单独评估。

### TGUI 主题配色 (2026-10-30 起)

- `UI.Theme.Slots` 已从"满屏单一亮绿 + 三档灰黑底"迁移到 **Catppuccin Mocha 风格暗色分层**:
  正文 `Normal` = 用户可见主色 `205,214,244` + Base 暗底 `24,24,37`; `HotNormal` 强调色为 Sky 冰青 `137,220,235`;
  选择高亮 `Focus` / `Active` / `Highlight` 均为 **亮白字 (`255,255,255`) + Surface1 蓝灰高亮条 (`69,71,90`)**;
  所有槽位背景统一到 `24,24,37`(高亮条与过滤框除外), 消除斑马纹观感。
- `UI.Theme.Slots.Editable` 为 **正文字 (`205,214,244`) + Surface0 深一档底 (`49,50,68`)** —— 过滤框输入文字始终清晰可读。
- 不变量**保留**: `Focus` / `Active` / `Highlight` 三槽位**完全同色** (见下方"新契约"), 否则两种焦点状态下选中行高亮不一致。
- `HotFocus` / `HotActive` (其他 View 的聚焦热区, TableView 不读取) 与高亮条取同色 `69,71,90` 底, 保持视觉一致。
- State 列文本由 [`Get-HostSelectorStateText.ps1`](../../ShellPrompt/Private/Get-HostSelectorStateText.ps1) 直接生成**纯字符串**（该函数输出即渲染终值, 不混入 SGR）——TG TableView 不解析单元格内联 ANSI, 且混入的转义字节会干扰 Wcwidth 宽字符列宽计算导致 `'⚠ 危险'` 吞空格; 仅在渲染边界保持净化的约束不变。
- 配色装配详见 [`docs/readme/tui-dashboard.md`](../readme/tui-dashboard.md) §2.9「配色契约」与槽位定义源码
  [`ShellPrompt/Private/Initialize-Config.ps1`](../../ShellPrompt/Private/Initialize-Config.ps1)
  （CHANGELOG 已收拢为存根, 历史条目不作现行设计依据）。

## 启动期时序 (2026-10-18)

profile 加载分为 3 个阶段, 各阶段目标与耗时归因:

| 阶段 | 内容 | 关键耗时 (本仓库现状) | 是否可优化 |
|---|---|---|---|
| 阶段 1 (欢迎语) | dot-source 5 个启动期文件 + AST 自检 | ~50ms (估) | 2026-10-29 去掉启动图缓存, 改为显式有序清单 |
| 阶段 2 (延迟初始化同步路径) | Invoke-DeferredInit: fnm (走缓存) + starship (同步 init, `-join "``n"` 后 iex) + PSReadLine import + set options | ~520ms + ~365~453ms (starship init 子进程) | starship init 是 profile 期最大单一开销 (回退到 P3 优化前的同步路径; PS 7.6+ 下 `&` 捕获的多行输出必须先 join 成单字符串再 `Invoke-Expression`, 否则参数绑定器拒收, 详见 profile 阶段 2 代码内注释) |
| 阶段 3 (首次调用 `sss` / `ssh-copy-id` 触发**懒加载** `Import-Module ShellPrompt`) | dot-source 全部 Private (2026-10-29 核对共 42 个 .ps1; `Initialize-Config` 由 psm1 先单独加载并守卫) + 加载 PwshSpectreConsole (+ 用户配置, 由 `Private/Initialize-Config.ps1` 加载) | ~960ms (估) | **架构级不变量, 改动前先在本文件核实设计**。注意: profile 启动期**不会**导入模块, 模块加载只发生在首次调用公开命令时 |

**Starship 同步 init**: 阶段 2 `Invoke-DeferredInit` 同步执行 `starship init powershell --print-full-init` (约 365~453ms 子进程), 由 starship 自身替换 `Function:prompt` 完成接管. 历史 P3 优化方案 (由 `Register-WttrPromptWrapper` wrapper 惰性触发 `Initialize-StarshipLazy`) 已随方案 B 部分回退一并移除 (该撤销未记入 CHANGELOG, 以源码与本文件为准).

**fnm env 缓存**: 阶段 2 `Invoke-DeferredInit` 调 `Initialize-FnmEnvironment`. 首次或 fnm.exe / node 版本列表变化时跑一次 `fnm env` 子进程并写 `$env:LOCALAPPDATA\ShellPrompt\fnm-env.json`; 后续启动直接读缓存 + 重算 PATH. **PATH 永不缓存** (避免静默覆盖用户临时 PATH 修改). 保底路径: 解析 aliases 目录失败时回退到同步执行 `fnm env` 子进程.

## 配色体系

本节是所有配色键 / Scheme 槽位 / 渲染层取色关系的速查表, 交互式 UI 单轨 Terminal.Gui v2 时代 (2026-10-30 起) 的唯一权威描述。任何颜色改动先查这里再动手。

### Colors 域（`$config.Colors.*`, 9 键）

全部定义见 [`Private/Initialize-Config.ps1`](../../ShellPrompt/Private/Initialize-Config.ps1) `Colors = [ordered]@{...}`, 值为带 ESC 的 ANSI 转义串, 渲染时由 `Get-CachedConfig -Section Colors -Key <键>` 命中 `$script:ColorCache` 快路径。

| 类别 | 键名 | RGB 默认 | 消费方 | 备注 |
|---|---|---|---|---|
| 主绿色系 | `FreshGreen` | 137,209,133 | Tables / 状态行（Spectre/ANSI 渲染） | 旧表格正文主色；2026-10-30 起 TG Scheme 槽位改用 Mocha 暗色分层 RGB 字面量, 不再引用本键 |
| 主绿色系 | `SageGreen` | 159,177,159 | 弱化绿语义 `Accent` | 旧 TG Scheme `HotNormal/ReadOnly` 取色来源; 2026-10-30 起槽位改用字面量, 键保留供 Spectre 输出 |
| 灰阶层 | `DarkGray` | 50,50,50 | 语义 `Dark`（当前无调用方请求） | 语义位保留, 未预热 |
| 灰阶层 | `MidGray` | 100,100,100 | 禁用态语义 `Muted` | 旧 TG Scheme `Disabled` 取色来源; 2026-10-30 起槽位改用 Overlay0 字面量 |
| 标题色 | `Cyan` | 112,199,209 | 语义 `Cyan`（当前无调用方请求） | Title 区配色已由 TG Scheme 接管 |
| 状态色 | `Danger` | 220,90,90 | State 列 `⚠ 危险` 语义标记 | TG TableView 无行级染色轻量入口, 语义落在 State 文本 |
| 状态色 | `Warning` | 220,180,80 | State 列 `⚠ 备选` 文字染色 (同上) | 同上 |
| 选中底 | `SelectedBg` | 112,199,209 底 + 近黑字 | 语义 `SelectedBg`（当前无调用方请求） | TG Scheme `Focus` 已接管高亮 |
| 复位 | `Rst` | (重置 ESC `\e[0m`) | 全部 Spectre / ANSI 输出末尾 | 必需, 漏写颜色泄漏 |

总计（2026-10-29 核对）：**9 键**。直接消费 **6 键**（`FreshGreen` / `SageGreen` / `MidGray` / `Danger` / `Warning` / `Rst`）/ 经 `$script:ColorSemanticMap` 保留语义但当前无调用方 **3 键**（`DarkGray` / `Cyan` / `SelectedBg`）。主绿色系的 RGB 值同时是 `UI.Theme.Slots` 的默认色来源，但 Scheme 槽位落地为 RGB 字面量，不经由 `Colors.*` 键读取。

> **2026-10-29 清理**：因长期无消费方已删除 5 键 —— `LightGray` / `White` / `BgDarker` / `Bold` / `Dim`。它们既不在 `$script:ColorSemanticMap` 里, 也没有任何直接读取点; 在 `config.ps1` 里继续配置会被静默忽略。

### UI 域 / `Theme.Slots`（10 槽位）

定义见同上 `Initialize-Config.ps1` `UI.Theme.Slots`, 键 = TG `Terminal.Gui.Drawing.Scheme` 的**反射实测可写**的属性名 (TG 2.4.10.0), 值 = `@{ Fg = 'R,G,B'; Bg = 'R,G,B' }`。

| Scheme 槽位 | 用途 | 引用 Colors 键 |
|---|---|---|
| `Normal` | 正文单元格 / 无焦点列头 / 列间竖线 | Mocha Text `205,214,244` + Base 暗底(24,24,37) |
| `HotNormal` | 标题/表头强调 | Sky 冰青 `137,220,235` + 暗底 |
| `Focus` | 聚焦列头 / 有焦点时选中行 | 亮白 `255,255,255` + Surface1(69,71,90) |
| `HotFocus` | 其他 View 的聚焦热区 (TableView 不读取) | — |
| `Active` | 无焦点时选中行 | 亮白 `255,255,255` + Surface1(69,71,90) |
| `HotActive` | 激活项热区 (TableView 不读取) | — |
| `Highlight` | 高亮标记 | 亮白 `255,255,255` + Surface1(69,71,90) |
| `Editable` | 过滤框输入区 | 正文字 `205,214,244` + Surface0 底 |
| `ReadOnly` | 只读行 | Overlay1 `127,132,156` |
| `Disabled` | 禁用行 | Overlay0 `108,112,134` |

> **不变量 (2026-10-18 建立, 2026-10-30 换色后仍适用)**: `Focus` / `Active` / `Highlight` 三个槽位**必须取同一颜色** (现为 `255,255,255` + `69,71,90`), 否则"焦点在表格"与"焦点在过滤框"两种状态下选中行高亮不一致, 且 IL 级实测确认 Focus 被聚焦列头和"有焦点时选中行"**共用**。Scheme 槽位颜色以 RGB 字面量直接配置在 `Initialize-Config.ps1`, 不经 `Colors.*` 键; 后两键 (`Danger`/`Warning`) 仍用于 State 列文本染色(渲染前剥离)。

实际装配入口: [`Private/Set-TguiTheme.ps1`](../../ShellPrompt/Private/Set-TguiTheme.ps1)（ALC 原生, 配色唯一路径）；幂等性 / 翻转防护 / TG 字典失配修复 详见该文件头部关键实现决策。

### 渲染层现状

- **TG v2 `TableView` 未暴露 per-row 染色的轻量入口** (`ColumnStyle.ColorGetter` 路线 α 反射实测可行但风险高, 当前**未启用**)。语义靠 State 列文本承担: `●` 已附着 / `⚠` 危险 / `⚠` 备选 / `✗` 不可用。
- 行级配色的 路线 α (反射 TG `ColumnStyle.ColorGetter`) 已实测可行但风险高 (依赖 TG IL 行为, 升级即可能破), 当前**未启用**, 留作 P1 候选。
- SSH 主机选择器与 `sss` 仪表盘共享同一套 `Focus == Active == Highlight` 语义, 因此配色改动只需调整 `UI.Theme.Slots` 一处。

### 主题切换约束

- TG `ThemeManager.Theme` 字典是配置驱动的, "新增 Scheme 名 + 设 `Theme`" 这条看似标准的路径会破坏 `SchemeManager` 内部状态 (后续 `GetScheme` 全部抛异常)。Set-TguiTheme 采取**就地覆写已存在方案实例**的策略, 刻意不新增方案名、不写 `ThemeManager.Theme`。
- 当前是**单主题** (`UI.Theme.Slots` 只一份), 不引入多主题 — 避免 TG 字典失配。
- 颜色微调只需改 `Colors` 域键值；Scheme 槽位翻转只需改 `UI.Theme.Slots` 里的 `Fg/Bg`。

### wttr 标题区配色

- Title 主色: 走 TG `Base.Focus` 与 `Menu.Normal` (由配色体系接管), 不直接读 `Colors.Cyan`。
- wttr 描述色: 客户端字典翻译后由 [`Private/Get-WttrTitleSuffix.ps1`](../../ShellPrompt/Private/Get-WttrTitleSuffix.ps1) 拼到 Title 末尾, 不做染色 (保留文本可读性, Title 区由 TG 配色统一)。
- 温度色: 同上。

## 提示符 wrapper（2026-10-18 起已移除）

本项目**不接管** `Function:prompt`. 历史版本中的模块侧 `Private/Register-WttrPromptWrapper.ps1` (含 starship lazy init / 锚点替换 / 底部 ASCII 栏拼接) 已于 2026-10-18 整体移除 (含配套 3 个 Pester 文件 + 4 个 Private 工具函数 + `Initialize-StarshipLazy.ps1`; 该撤销未记入 CHANGELOG, 以源码与本文件为准). 用户的 prompt 由 starship 原生接管 (`profile 阶段 2` 同步执行 `$starshipInit = & $starship init powershell --print-full-init; Invoke-Expression ($starshipInit -join "`n")`, PS 7.6+ 必须先 join), 提示符样式不受本项目约束.

**`Microsoft.PowerShell_profile.ps1` 的边界**: profile 始终**仅**做模块加载 + 环境初始化 + 启动配置, 不持有任何 wttr 业务代码 (符合 AGENTS.md 的"profile 不放业务逻辑"原则).

## 交互 UI 标题行天气（2026-10-18 起, 方案 R2）

SSH 主机选择器的 TGUI **标题行**（整窗行 0）自动追加一行 wttr 天气短串 (如 ` - Shanghai: 🌫 +18°C`). 拼装入口在 [`Private/Show-HostSelector.ps1`](../../ShellPrompt/Private/Show-HostSelector.ps1) 分发器拼装 `-Title` 参数之前的 `Get-WttrTitleSuffix` 调用点:

- 在拼装 `-Title` 参数之前, 由 [`Private/Get-WttrTitleSuffix.ps1`](../../ShellPrompt/Private/Get-WttrTitleSuffix.ps1) 判定 `$script:Config.Weather.Enabled` 并调用 `Get-WttrWeather -Format CustomUrl -Url 'https://wttr.in/?format=j1&lang=zh' -CacheMinutes 10 -ErrorAction SilentlyContinue`, 自解析 j1 JSON 拼出 ` - <City>: <中文描述> <Temp>°C` 片段;
- 启用且 wttr 非空时, 把 ` - <wttr>` 拼到原标题末尾; 否则 `$wttrSuffix` 留空, 标题原样渲染;
- `Get-WttrWeather` 自带超时/失败兜底(返回 `''`), 此处再加 `IsNullOrWhiteSpace` 兜底, 永不抛异常, 永不破坏标题行;
- 数据源: [`Private/Get-WttrWeather.ps1`](../../ShellPrompt/Private/Get-WttrWeather.ps1) (`$script:_WttrCache` 缓存键 = `"Format|Url"`);
- 副作用: 提示行草案 A.2 已撤回, `Write-GridViewHint` 已**不再**渲染天气片段 (上一轮挂在提示行末尾的逻辑已撤掉), 避免与标题区重复显示; 该函数本身已于 2026-10-29 一并删除(无生产调用方).

`Weather` 配置域现为两个键 (历史 wrapper 时代的 7 键已随移除收缩): `Weather.Enabled` (总开关, 默认 `$true`) 与 `Weather.ExtraWeatherDescMap` (用户扩展中文字典, 默认 `[ordered]@{}`), 定义见 [`Private/Initialize-Config.ps1`](../../ShellPrompt/Private/Initialize-Config.ps1); 细则见 [`docs/agents/wttr.md`](wttr.md).
