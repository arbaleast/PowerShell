# 🖥️ tmux 管理器 TUI 仪表盘

本文记录 `sss`（[`Start-TmuxSession`](../../ShellPrompt/Public/Start-TmuxSession.ps1)）tmux 管理器仪表盘的**结构与交互契约**。

---

## 一、当前状态

`sss` 的仪表盘现在只有**一条轨**（2026-10-30 用户裁定移除 PSTui 回退轨）：

| 轨 | 渲染实现 | 状态 |
|---|---|---|
| **Terminal.Gui 轨**（唯一） | **独立的 Terminal.Gui v2 应用**（`Show-TmuxTuiDashboard`） | 现行实现，真机验收通过（2026-10-30 `5d5daac`） |

> 仪表盘**只有这一条轨**：仓库中不存在第二条仪表盘渲染路径，也没有与之配套的渲染开关配置。**PSTui 依赖本身已同日（2026-10-30）随 `Modules/PSTui` 删除**——SSH 主机选择器也已迁至这一条 vendored Terminal.Gui v2 轨（见下）。

- Terminal.Gui 轨是**独立应用**，不是"套了 Terminal.Gui 装饰的表格弹窗"：Terminal.Gui 自己负责布局、绘制、表格、选择、键盘、缩放与状态栏；仓库既有的 PowerShell 业务层（`Invoke-TmuxSessionFetch` / `Get-TmuxSessionState` / `Invoke-TmuxAttach` / `New-TmuxSession` / `Invoke-TmuxSessionDeletion` / `Invoke-SshCommand`）继续负责 SSH 与 tmux，**Terminal.Gui 不重写任何 SSH/tmux 逻辑**。
- SSH 主机选择器（[`Show-HostSelector`](../../ShellPrompt/Private/Show-HostSelector.ps1)）已同日迁至同一 vendored Terminal.Gui v2 轨，与仪表盘共用"组装层 + 编排层"拆分（`New-TguiHostSelectorWindow` / `Invoke-TguiHostSelector`）；原 PSTui 链路与 `Invoke-GridViewPrompt` 随 `Modules/PSTui` 删除。
- 原 GridView 轨的其余 `Out-ConsoleGridView` 能力不迁入：会话删除改走仪表盘当前选中行，不再弹嵌套列表；tmux 会话列表菜单已不存在。

下文第二章描述 Terminal.Gui 轨的运行契约，第三章给出 vendored 依赖（Terminal.Gui）的归属结论。

---

## 二、Terminal.Gui 轨

### 2.1 程序集加载

Terminal.Gui 从仓库内置的 vendored 程序集加载：

- 载入源：`Modules/Terminal.Gui/<最高版本目录>/Terminal.Gui.dll`（版本钉 **2.4.10.0**；2026-10-30 自 `Modules/PSTui/1.0.5/` 迁出，全仓库单副本）。
- 载入方式：**独立可回收 `AssemblyLoadContext`**（[`Get-TguiContext`](../../ShellPrompt/Private/Get-TguiContext.ps1)），带路径解析回调连带加载同目录依赖（`System.IO.Abstractions` / `Wcwidth` / `ColorHelper`）。
- 该上下文是**幂等**的：首次调用加载并缓存，后续复用；依赖或程序集缺失时抛可定位的终止错误，不静默降级。
- Terminal.Gui 的 **vendored 归属**（是否拆成独立依赖目录、版本如何管）见 [第三章](#三vendored-依赖归属terminal-gui-放哪)。

> 本文涉及的 Terminal.Gui API 行为均来自对 vendored **2.4.10.0** 的反射探针实测（探针报告：`.agent_cache/tgui-probe/REPORT.md`），**不是按文档示例假定**。

### 2.2 屏幕布局

整窗由 [`New-TmuxTuiDashboardWindow`](../../ShellPrompt/Private/New-TmuxTuiDashboardWindow.ps1) 组装，**三段式**：

```text
┌──────────────────────────────────────────────────────────────────┐
│ ShellPrompt TMUX Manager  |  主机: debian  |  已连接            │ ← 标题行
│ 会话: 3  Attached: 1  Detached: 2                              │ ← 统计行
│ (空态提示 或 错误码 + 原因 + 可执行提示；有会话时留空)          │ ← 辅助行
├──────────────────────────────────────────────────────────────────┤
│ #   SESSION          STATUS      WINDOWS                        │ ← 会话表
│ 1   tmux-100001      Attached           2                      │
│ 2   tmux-100002      Detached           1                      │
├──────────────────────────────────────────────────────────────────┤
│ Enter 附着  n 新建  r 刷新  s SSH  x 删除  q 退出  Esc 退出       │ ← 快捷键栏
└──────────────────────────────────────────────────────────────────┘
```

- **顶部状态区固定 3 行**：标题行 `ShellPrompt TMUX Manager | 主机 | 连接状态`；统计行 `会话: N  Attached: N  Detached: N`；第三行仅在**空态**或**错误态**时使用。
- **中间是会话表**，列固定为 `# | SESSION | STATUS | WINDOWS`：`WINDOWS` **右对齐**；`SESSION` 拿走剩余宽度（列宽计划见 [`New-TmuxTuiColumnPlan`](../../ShellPrompt/Private/New-TmuxTuiColumnPlan.ps1)）。
- **底部是固定快捷键栏**（Terminal.Gui `StatusBar` + `Shortcut`），贴底一行。
  渲染契约(2026-10-30 真机+子视图取证)：TG 2.4.10 的 `Shortcut` 屏幕渲染序 = **键名 → HelpText → Title**，
  故工厂层 `Title = 纯标签`、`HelpText = ''` —— HelpText 再放标签会把"键 标签"渲染两遍。
- 窗口 `BorderStyle` 置空：置空后窗口内容区等于整个 Frame，绝对行号才与屏幕行号对齐。

### 2.3 状态分型

视图模型由 [`ConvertTo-TmuxTuiViewModel`](../../ShellPrompt/Private/ConvertTo-TmuxTuiViewModel.ps1) 一次成型，分三态：

| 模式 | 触发条件 | 表现 |
|---|---|---|
| `Session` | 探测成功且确有会话 | 会话表正常渲染，辅助行留空 |
| `Empty` | 探测成功但确实没有会话 | 会话表为空，辅助行给操作提示（如 `N 新建 / R 重试 / S 直连`） |
| `Error` | 探测失败 | 会话表为空，辅助行给**错误码 + 原因 + 可执行提示** |

两条硬约束：

1. **错误码与长错误文本绝不进会话表行**——它们只出现在顶部辅助行。空态与错误态也**不伪造占位行**。
2. **空态与错误态严格区分**：探测失败永远不会显示成"没有会话"（错误码由 `Get-TmuxErrorCode` 给出，取值与含义见第五章错误码表）。

### 2.4 键位

底部快捷键栏（[`New-TmuxTuiShortcutList`](../../ShellPrompt/Private/New-TmuxTuiShortcutList.ps1)）：

| 键 | 动作 | 需要会话 | 说明 |
|----|------|----------|------|
| `Enter` | 附着/恢复选中会话 | **是** | 无会话时**不出现** |
| `N` | 新建 tmux 会话 | 否 | |
| `R` | 刷新会话列表 | 否 | |
| `S` | 直连 SSH | 否 | |
| `X` | 删除选中会话 | **是** | 无会话时显示为 `[X] 删除 (不可用)` |
| `Q` | 退出管理器 | 否 | |
| `Esc` | 退出管理器 | 否 | 走 Terminal.Gui 内建 Quit 路径（见 2.6） |

- 无会话时**附着项不绑定也不出现**，**删除项不绑定、且明确标注 `(不可用)`**——不可用状态是显式展示，不是静默隐藏。
- `X` 删除走 `Invoke-TmuxSessionDeletion`，**二次确认在业务函数内**，本层不复刻确认逻辑（防拆这道防误删闸）。
- 动作值以 `Get-TmuxActionDefinition` 为**唯一事实来源**（快捷键栏工厂直接消费它），UI 层不另立一份键位表。

### 2.5 终端所有权（关键规则）

Terminal.Gui 轨里，**Terminal.Gui 是终端的唯一所有者**：

- Terminal.Gui 自己管理备用屏（`ESC[?1049h` / `ESC[?1049l`）。
- 仓库自有的 `Enter-TmuxAlternateScreen` / `Exit-TmuxAlternateScreen` 在该轨下通过 `$script:TmuxTerminalOwner = 'Tgui'` **整体静音**，因此**只有一层备用屏**，不会出现双层嵌套。
- `Application.Shutdown()` 负责还原光标 / 鼠标 / 粘贴 / 备用屏；**正常退出、Ctrl+C 与异常路径**都会走到。
- 驱动名固定为 **`'ansi'`**：`DriverRegistry` 只注册 `'windows'` / `'dotnet'` / `'ansi'` 三个驱动，而 `'dotnet'` 驱动的输入层**无视 `AppModel` 无条件发备用屏序列**，`'ansi'` 驱动才让 `AppModel` 生效——固定 `'ansi'` 才能保证"TG 独占终端"在 Windows Terminal 与 Linux 上行为一致。
- 附着 / 新建 / 直连 SSH 这三个全屏业务子动作在 TG 事件循环**退出并 Shutdown 之后**才执行，执行完主循环重新 `Init`，天然恢复到仪表盘。

### 2.6 键盘与缩放

Terminal.Gui 2.4.10 上踩过并固化的三条规则：

1. **`Shortcut.BindKeyToApplication` 必须置 `$true`**：默认 `$false` 时 Shortcut 只登记进自己的键表，应用级键表里没有它，真实按键永远到不了 `Action`——状态栏会退化成纯展示件。
2. **`Shortcut.Command` 必须保持 `NotBound`**：若同时设成 `Accept`，会形成 `InvokeCommandsBoundToKey → RaiseActivated → DefaultHotKeyHandler → InvokeCommands → InvokeCommandsBoundToKey` 的死循环，**StackOverflow 崩进程**。
3. **`Esc` 不由仪表盘绑定**：应用级键表默认已绑定 `Esc → Quit`，重复登记会抛 `A binding for Esc exists`。因此 `Esc` 退出走 Terminal.Gui 内建的 Quit 路径，快捷键栏里的 `Esc` 项只承担**展示**职责；编排层把"事件循环返回且无待处理动作"一律判定为用户主动退出。

**缩放**：表格高度用 `Dim.Fill(Dim.Absolute(1))`、快捷键栏用 `Pos.AnchorEnd()`，因此终端尺寸变化时布局**自动重排**，表格与快捷键栏之间**零重叠、零空档**。`Application.ScreenChanged` 触发重建，**列计划按新宽度重算**——窄窗口下**次要列自动隐藏**（`STATUS` 在终端 < 96 列时隐藏，`WINDOWS` 在 < 72 列时隐藏）。

**选中**：Terminal.Gui 2.4.10 的 `TableView` **没有** `SelectedRow` 属性，选中行读 `TableView.Value.SelectedCell.Y`；刷新后按**会话名**保留选中。

### 2.7 配置

`UI` 域当前只剩 **`UI.Theme`**（TGUI 配色槽位，见 [`Private/Initialize-Config.ps1`](../../ShellPrompt/Private/Initialize-Config.ps1)）。

> 原 `UI.GridViewFocus` / `UI.GridViewFullScreen` / `UI.DashboardTuiEnabled` / `UI.DashboardFullScreen` 均已随 PSTui 轨与自研回退轨移除（2026-10-30）；旧键残留在 `config.ps1` 里无渲染开关效果（静默忽略），无害。

> `UI` 域是 `[ordered] OrderedDictionary`，条目**不是 PowerShell 属性**：判键存在要用 `.Contains('X')`，取值用 `['X']`——用 `.PSObject.Properties['X']` 判存在恒为 `$null`，开关会永远不生效。

### 2.8 非交互终端护栏

输入或输出被重定向（管道 / CI）时，Terminal.Gui 的 `Init` **不会抛异常**，但事件循环会永久阻塞。因此仪表盘在触碰 TG 之前先判定 `[Console]::IsInputRedirected` / `[Console]::IsOutputRedirected`，命中则直接跳过并返回。

### 2.9 配色契约（ALC 原生主题）

**Terminal.Gui 轨必须自带一套主题装配**，不沿用默认加载上下文 `Add-Type` 轨的旧 `Set-TgColorScheme`（该函数已随 PSTui 于 2026-10-30 删除，现役唯一配色路径就是 ALC 原生 `Set-TguiTheme`）：

| 事项 | 事实 |
|------|------|
| 载入方式不同 | 旧默认加载上下文轨（`Add-Type`）已随 PSTui 删除；仪表盘与主机选择器走**独立 ALC**（§2.1）。同名类型跨程序集是**两套类型身份**，互相赋值抛 `Cannot convert ... Scheme to ... Scheme` |
| 内置 `Base` 方案不可见 | 实测 `SchemeManager.GetScheme('Base').Normal` = 前景 `(255,255,255)` / 背景 `(255,255,255)` —— **白对白，文字隐形**；`'ansi'` 驱动不做终端颜色探测，故该状态恒定 |
| 视图默认方案名不统一 | `Window → 'Base'`、`StatusBar → 'Menu'`、`Label` / `TableView → ''`（回退 `'Base'`） |

因此仪表盘轨用 [`Set-TguiTheme`](../../ShellPrompt/Private/Set-TguiTheme.ps1) 做 **ALC 原生**装配：

1. **就地覆写已存在的方案实例**（`SchemeManager.GetScheme(name)`）的槽位，槽位表沿用 `UI.Theme.Slots`；**不新增方案名、不写 `ThemeManager.Theme`**（该组合会打坏 `SchemeManager` 内部字典与 `Theme` 的对应关系）。
2. **逐槽位等值跳过**：TG 2.4.10 把与现值相同的 `Attribute` 再写一遍不是幂等 no-op，而是触发一次 Scheme 重建并把槽位打回内置默认（实测 4 轮交替翻转）。
3. **显式绑定方案**：`Window` / 状态行 / 会话表绑 `Base`，快捷键栏绑 `Menu`；绑定前用 `Test-TguiSchemeVisible` 过滤"前景 = 背景"的不可见方案，`Resolve-TguiScheme` 再按候选顺序挑第一个**可见**的实例——**界面绝不允许因为配色而空白**。

> 构造 `Attribute` 的坑：其构造函数形参是 `Color&`（byref）。PowerShell 的 `[ref]$c` 是 `PSReference`，反射 `Invoke` 时无法转换成 `Color&`；正确姿势是把装箱后的 `Color` **直接放进 args 数组**，由运行时取数组元素地址作为 byref 实参。

### 2.10 事件循环契约（必须用非泛型 `Run`）

**`Application.Run<Window>(handler, driver)` 不能用来运行已组装好的窗口。**

| 事项 | 事实（2.4.10 实测） |
|------|------|
| 泛型重载的约束 | `where T : IRunnable, new()` —— 带 `new()` 约束 |
| 泛型重载干了什么 | `ApplicationImpl.Run<TRunnable>` 内部 **new 一个全新的 `T`**，装箱成 `IRunnable` 交给 `Run(IRunnable, Func)` 跑完再 `Dispose`（IL：`call <new T>` → `box` → `call Run` → `isinst IDisposable` → `Dispose`） |
| 后果 | 传入的窗口**从未上屏**；真机跑的是一个**全新空 Window**，只画边框 —— 表现为「**只剩边框、内容全无**」；Esc/应用级键表仍可用，故看起来"活着" |
| 正确姿势 | 用**非泛型** `Application.Run(IRunnable, Func<Exception,bool>)`，把**组装好的窗口实例**传进去（该重载内部 `Begin(runnable)` 后进事件循环） |

```powershell
# 正确: 传组装好的窗口
$runArgs = [object[]]::CreateInstance([System.Object], 2)
$runArgs[0] = $result.Window
$runArgs[1] = $errorHandler
[void]$runMethod.Invoke($null, $runArgs)
```

> 行为级判据（探针 `.agent_cache/tgui-probe/p63-run-which-window.ps1`）：同一窗口实例 `W`，泛型路径下 `W.IsRunning` 始终为 `False`（跑的是别的实例），非泛型路径下为 `True`（跑的就是 `W`）。
>
> `Run` 的 `errorHandler` 只把异常存进 `$global:TguiError` 并结束循环，**事件循环返回后必须消费它**（否则渲染异常表现为"仪表盘无声退出"）。

### 2.11 Init 周期与事件订阅

仪表盘的 `while` 循环每轮都是 `Init → Run → Shutdown`（附着/新建/删除/刷新之后回仪表盘）。2.4.10 实测两条事实：

| 事项 | 事实 |
|------|------|
| `Shutdown` 会清空事件订阅 | `ApplicationImpl.ScreenChanged` 的处理器数 `1 → 0` |
| `Application.Instance` 不随周期变化 | `Init → Shutdown → Init` 之后**仍是同一个对象**（`ReferenceEquals = True`） |

⇒ 只按"实例标识"去重的订阅守卫会在第二轮误判"已订阅"而跳过，结果是**第一次交互之后 resize 不再触发重建**。因此编排层在 `Shutdown` 之后必须清掉"本轮已订阅"标记（`$global:TguiSubscribedApp = $null`），让下一轮重新订阅。

### 2.12 依赖与启动耗时（阶段 C 实测）

| 事项 | 实测值 / 事实 |
|------|------|
| Terminal.Gui 版本 | **2.4.10.0**，vendored 于 `Modules/Terminal.Gui/2.4.10/`（**已入版本库**，全仓库单副本；2026-10-30 自 `Modules/PSTui/1.0.5/` 迁出） |
| PSTui | **已删除**（2026-10-30）—— SSH 主机选择器亦已迁至本轨 Terminal.Gui v2（见 §一） |
| 模块导入耗时 | ≈ **207 ms**（冷导入，`-NoProfile`） |
| 导入后是否已加载 TG | **否** —— 惰性加载，模块导入**不**给 Shell 启动增加负担 |
| `Get-TguiContext` 首次 / 二次 | **28.9 ms** / **1.2 ms**（ALC 与 TG 反射句柄有缓存） |
| 仪表盘窗口组装 | 首次 ≈ **840 ms**（TG 静态初始化 + JIT，一次性），稳态 ≈ **30–45 ms** |
| CI 触发路径 | `ShellPrompt/**`、`Modules/**`、`Microsoft.PowerShell_profile.ps1`、workflow 本身 —— vendored 依赖（`Modules/Terminal.Gui/2.4.10/` 的 DLL 等）变更同样会改变仪表盘行为，故 `Modules/**` 必须触发 CI。⚠️ 该路径补齐已本地提交（`e415424`），**尚待有 `workflow` scope 的凭据推上**——OAuth 凭据缺该 scope 时 GitHub 会整体拒绝含 workflow 变更的推送 |

---

## 三、vendored 依赖归属（Terminal.Gui 放哪）

> **2026-10-30 更新**：PSTui 已整体删除，Terminal.Gui 随之迁到**独立目录** `Modules/Terminal.Gui/<ver>/`（当年评估记录里的方案 B）。下表为**现状**；§3.2 的三方案评估作为历史决策记录保留（方案 A 的"与 PSTui 同目录"前提已失效）。

### 3.1 现状（事实）

| 事实 | 值 |
|------|---|
| Terminal.Gui 版本 | **2.4.10.0**（`AssemblyVersion` = `AssemblyFileVersion`），目标框架 `.NETCoreApp,v10.0` |
| vendored 位置 | `Modules/Terminal.Gui/2.4.10/` —— **单一副本**，独立版本目录入版本库（2026-10-30 纯 rename 自 `Modules/PSTui/1.0.5/` 迁出，无内容变更） |
| 同目录托管依赖 | `ColorHelper` / `JetBrains.Annotations` / `Markdig` / `Microsoft.Extensions.DependencyInjection.Abstractions` / `Microsoft.Extensions.Logging.Abstractions` / `Onigwrap` / `System.IO.Abstractions` 系列 / `Testably.Abstractions.FileSystem.Interface` / `TextMateSharp(.Grammars)` / `Wcwidth`（共 13 个依赖 DLL，随目录一并迁入） |
| 消费方 | `sss` 仪表盘与 SSH 主机选择器 —— **独立可回收 ALC**（`ShellPrompt-Tgui`），依赖按"同目录同名文件"回载 |
| 同进程内的 TG 类型身份 | **一套**（`ShellPrompt-Tgui` ALC）；原"默认上下文第二套"已随 PSTui 删除，不存在 |

### 3.2 结论：**独立目录、单副本**（2026-10-30 起）

当年（PSTui 仍在时代）评估过三种布局，评估记录保留如下；"维持现状（方案 A）"的 **PSTui 前提已随 PSTui 删除失效**，采用的是其中的方案 B：

| 方案 | 后果 | 判定 |
|------|------|------|
| A. 维持现状（TG 与 PSTui 同目录，单副本） | 两条消费路径加载**同一个文件**，版本必然一致；无重复体积 | ✅ 当年采用；2026-10-30 PSTui 删除后**失效** |
| B. TG 移到 `Modules/Terminal.Gui/<ver>/`，PSTui 目录留副本 | 两份 TG 二进制进版本库（+9 MB），版本漂移不可见；"哪份才是真的"对后来者是坑 | ❌ 当年不采用；**PSTui 删除后即为现状**（PSTui 目录不复存在，无"第二份"问题） |
| C. TG 移到独立目录，默认上下文预加载后给 PSTui 用 | PSTui 的 GridView 改为依赖"别处预加载的程序集"——**新的失败模式**（预加载失败即主机选择器失效）；仪表盘 ALC 仍要自己再载一份 | ❌ 不采用（该失败模式随 ALC 化主机选择器一并消失） |

现行格局的判定依据：

1. **TG 是全仓唯一的交互式 UI 依赖**，独立版本目录 + 独立 ALC 的组合天然满足"单副本、版本钉死、类型身份一致"。
2. ALC 从独立目录按同目录规则解析依赖；"主机选择器能否弹出"由 [`Get-ConsoleUiBackend`](../../ShellPrompt/Private/Get-ConsoleUiBackend.ps1) 的 vendored 目录探测显式兜底，不再是隐式的程序集预加载。
3. 版本耦合的风险由**显式失败**兜住：加载器对核心类型面逐项探针，vendored 版本一变就抛 `TGUI 载入失败: Terminal.Gui 中缺少核心类型 …`，并指回 [`Get-TguiContext.ps1`](../../ShellPrompt/Private/Get-TguiContext.ps1) 头部的 API 面记录（§2.1）——不是静默半屏。

> 因此**不做回迁**：不改 vendored 目录结构，也不改程序集加载方式。

### 3.3 升级 Terminal.Gui 的固定动作

1. 替换 `Modules/Terminal.Gui/<ver>/` 下的 TG 与同目录依赖；
2. 重跑反射探针，逐条核对 `Get-TguiContext.ps1` 头部的 API 面记录；
3. 同步本文件 §2.1 / §3.1 的版本与依赖清单；
4. 跑三道门禁（Pester / PSScriptAnalyzer / Profile 冒烟）。

> 护栏：`ShellPrompt/Tests/Get-TguiContext.Tests.ps1` 断言 TG 就在 `Modules/Terminal.Gui/<ver>/` **独立目录单副本**（有人引入第二份 `Terminal.Gui.dll`、或把 TG 迁回任何其他目录时该断言失败，强制走一次显式决策）。

## 四、错误码表

| 错误码 | 含义 | 判定依据 | 用户指引 |
|--------|------|----------|----------|
| `E_SSH_TIMEOUT` | SSH 等待超时（作业被 Kill），与"远端命令失败"是两回事 | 探测结果标记超时 | 按 `r` 重试 · 按 `s` 直连 SSH |
| `E_SSH_UNREACHABLE` | 网络不可达 / 端口被拒绝 / DNS 失败 | 探测结果标记网络错误 | 按 `r` 重试 · 按 `s` 直连 SSH |
| `E_SSH_AUTH` | SSH 认证或主机密钥校验失败 | 错误文本命中认证关键字（如 `Permission denied` / `Host key verification failed`） | 按 `r` 重试 · 按 `s` 直连 SSH |
| `E_SSH_FAILED` | SSH 进程或远端命令失败（退出码非 0） | 退出码非 0 | 按 `r` 重试 · 按 `s` 直连 SSH |
| `E_NO_TMUX` | 命令跑通了但拿不到 tmux 版本（远端未安装 tmux / tmux server 未运行） | 退出码 0 且无版本信息 | 按 `r` 重试 · 按 `s` 直连 SSH |
| `E_UNKNOWN` | 没有任何探测信息（兜底，理论不可达） | 探测结果为空 | 按 `r` 重试 · 按 `s` 直连 SSH |

错误码只出现在**顶部辅助行**（与错误原因、可执行提示同行）；会话表行内**永不出现**错误码或长错误文本（见 §2.3 硬约束 1）。

---

## 五、已知限制 / 修复台账

### 真机缺陷修复台账（2026-10-30，全部已复验或含真机证据）

| # | 真机现象 | 根因（取证方式） | 修复（commit） |
|---|----------|------------------|----------------|
| 1 | 仪表盘只剩边框、内容全无 | ① TG 内置 `Base` 方案白对白（IL 取色取证）；② 编排层误用泛型 `Run<T>` ⇒ 内部新建空窗上屏（IL/行为判据） | ALC 原生主题 `Set-TguiTheme` + 非泛型 `Run(IRunnable, Func)`（`45adc55` / `7bf3e8e`） |
| 2 | 首次交互后拖拽缩放失灵 | `Shutdown` 清空事件订阅而 `Application.Instance` 跨 Init 周期不变（IL + 订阅计数） | Shutdown 后清"本轮已订阅"标记（`102035e`） |
| 3 | "获取远程 tmux 会话" 反复出现、仪表盘从不上屏 | 主循环每轮无条件取数 + 尺寸记账(Post-Init 读取)与 `ScreenChanged` 报数错位 ⇒ 重建风暴（代码审查 + 契约护栏） | 取数受 `$state` 守护 + 记账以事件报数为准 + 同轮事件单次放行（`dbd15ca`） |
| 4 | 底栏快捷键每项渲染两遍 | `Shortcut` 屏幕渲染序 = 键名 → HelpText → Title（IL + 子视图取证），旧工厂 Title/HelpText 双放标签 | `Title=纯标签, HelpText=''`（`80794d1`） |

### 真机验收记录（2026-10-30，Windows Terminal + pwsh 7.6.3，arbaleast@G7）

- **已通过**（本轮逐项回填）：#0 内容可见；#5 附着/ detach 交接；#6 新建（n：真实创建后 detach 回仪表盘并刷新，Esc 取消回退）与删除（x：二次确认 `[y/n]` 默认 n）；#2 键位单次触发；#4 缩放（窄窗 STATUS 列按设计隐藏、底栏单渲染、无残影）；#7 SSH 直连（exit 后回仪表盘）；#8 终端还原（备用屏退出后 Shell 历史完整、无双底栏、无 1049 残留）；#9 无 TTY 护栏。
- **遗留风险（不阻断收口）**：
  1. 空态/错误态的"独立空态行"回填证据以文字确认为准（回填截图实际含 1 个会话），未逐字节取证；
  2. 极窄宽度（40–71 列）与 40×10 下限场景未逐档真机复验（无头布局核验零重叠零越界）；
  3. conhost 宿主未验证（本轮仅 Windows Terminal）。
- 仪表盘当前**只有一条轨**（见 §一）；若真机再出问题，历史实现走 git 历史回查，不留在工作树。

- **终端宽度下限 40 列**：仪表盘按 **40×10** 起步（`New-TmuxTuiDashboardWindow` 的 `ValidateRange` 与编排层的屏幕夹取一致）。真实终端窄于 40 列时，仪表盘会按 40 列布局 ⇒ **该极端场景存在横向溢出**。宽度 ≥ 72 列起隐藏 WINDOWS 列、≥ 96 列起隐藏 STATUS 列（见 §2.4），三档目标尺寸（100×30 / 120×35 / 160×45）不受影响。
- **首次拉起的一次性延迟**：首次进入 `sss` 时 Terminal.Gui 静态初始化 + JIT 约 **0.84 s**（之后稳态 30–45 ms）；模块导入阶段**不**加载 Terminal.Gui（惰性），因此不影响 Shell 启动耗时。详见 §2.12。
- **绘制级断言无法无头执行**：Terminal.Gui 2.4.10 未暴露 `FakeDriver` / 公开的 `View.Render`，无头证据止于方案配色值、布局几何、IL 反汇编与子视图/`IsRunning` 行为探针；"内容确实可见"由真机清单第 0 项确认（已通过）。

### 真机验收清单（Windows Terminal + pwsh 7.6+，逐项打勾）

准备：对一台真实 tmux 主机运行 `sss`（无渲染开关，仪表盘只有一条轨）。

| # | 验收点 | 通过标准 |
|---|--------|----------|
| 0 | **内容可见** | 标题行、统计行、会话表单元格、快捷键栏的**文字全部可见**（不是"只有边框"）；前景与背景不同色 |
| 1 | 布局观感 | 顶部标题/主机/连接状态、统计行、会话表格、底部快捷键栏各占一行；100×30 / 120×35 / 160×45 三档均无遮挡叠行 |
| 2 | 键位 | ↑↓ 移动选中、Enter 附着、N 新建、R 刷新、S 直连、X 删除（二次确认）、Esc/Q 退出，各键一次触发（无重复分发） |
| 3 | 空态/错误态 | 无会话时独立空态行（不伪造表格行）；断网时错误码 + 指引在辅助行，表格区不出现错误文本 |
| 4 | 缩放 | 运行中拖拽窗口尺寸：整窗重建无残影；窄窗口 STATUS/WINDOWS 列自动隐藏 |
| 5 | 附着交接 | Enter 附着 → 仪表盘消失 → 真实 tmux 全屏；detach（`d`）→ 仪表盘重新出现且会话列表已刷新，选中行尽量保持 |
| 6 | 新建/删除交接 | N 新建（或 Esc 取消：**不发生屏幕翻转**）回到仪表盘；X 删除含二次确认（默认 n），完成后回仪表盘刷新 |
| 7 | SSH 直连交接 | S 直连 → 全屏 ssh；exit 后回仪表盘 |
| 8 | 终端还原 | Q/Esc、**Ctrl+C**、Ctrl+C + 异常路径退出后：光标/输入模式正常、Shell 历史完整、无双底栏、无 1049 残留（备用屏单层：TG 独占，模块不发 1049） |
| 9 | 无 TTY 护栏 | `pwsh -c "Start-TmuxSession deb"`（非交互重定向）不挂死，直接返回并给出跳过警告 |

登记结果时注明日期与窗口宿主（Windows Terminal / conhost）。

### SSH 主机选择器真机验收清单（TGUI 新轨 `Invoke-TguiHostSelector`，2026-10-30 迁移，**全部标"未验证"**）

> 2026-10-30 PSTui 移除后，主机选择器改由 ALC 原生 Terminal.Gui v2 承接
> （组装层 + 事件循环，与仪表盘共享终端生命周期）。无头三门禁（Pester
> 338/338 / PSSA / Profile 冒烟）已通过 **无头可测** 的部分：整窗组装、
> 过滤回填、预选、非交互护栏（重定向环境直接返回 `$null` 不阻塞）、
> 分发器业务装配。以下交互行为依赖真实 TTY，**均未经真机验证**，
> 不得凭无头探针宣称通过。

准备：`Clear-Host` 后对一台含 3+-主机的 ssh config 运行 `Start-TmuxSession`
（进入主机选择器），窗口宿主 = Windows Terminal + pwsh 7.6+。

| # | 验收点 | 通过标准 |
|---|--------|----------|
| 0 | **内容可见** | 标题行（含主机数 + wttr 后缀）、"搜索: " 输入框、HOST/STATE 表头、底部提示行全部可见，前景背景不同色 |
| 1 | **搜索过滤** | 行 1 输入框打字即时过滤（如输入 `deb` 只剩匹配行）；Backspace 清空恢复全量；从未空到再恢复不崩（空匹配行时 Enter 不产生结果也不退出） |
| 2 | **键位** | ↑↓（Tab 切到表格后）移动选中；Enter 确认 → 返回 `.Value`=主机名并继续业务流程；Tab 在输入框↔表格间切换焦点 |
| 3 | **Esc 可达性（重点风险项）** | **搜索框聚焦时**按 Esc 立即退出（取消双保险：`FilterField.KeyDown` 直判 Esc）；若发现"按 Esc 无反应"，说明 Esc 被 TextField 消费且双保险未覆盖 —— 按缺陷回报，不允许以"先 Tab 再 Esc"作为代替放行 |
| 4 | **Ctrl+C** | 焦点在输入框或表格时 Ctrl+C 均立即退出，不创建任何 tmux 会话也不落 SSH |
| 5 | **LastHost 行为** | 上次连接的主机置顶且 STATE 列= "★ 最近"；选中后连接成功，下次进入仍置顶（业务回归） |
| 6 | **缩放** | 运行中拖拽窗口：整窗重建无残影、过滤文本/选中行保留；窄终端（40-70 列）横向不溢出 |
| 7 | **中文/Unicode** | 中文主机名、wttr 中文天气串列宽正确（无粘连/截断/孤立半角空格） |
| 8 | **终端还原** | Esc 与 Ctrl+C 退出后：备用屏退层（无 1049 残留）、光标正常、Shell 历史完整、无双提示行 |
| 9 | **返回值契约** | Esc → 下游不建会话不连 SSH（Start-TmuxSession 直接退出路径）；Enter → 连接参数与迁移前一致（目标主机 .Value 透传） |

Linux SSH 终端 + pwsh 7.6+ 侧另跑一轮 #0/#1/#3/#4（`'ansi'` 驱动路径）。
登记结果时注明日期 + 窗口宿主 + 宿主 OS。

---

## 相关文档

- [架构](architecture.md) —— 模块目录树与加载流程
- [命令一览](commands.md) —— 公开命令与交互流程
- [配置](configuration.md) —— 配置域与优先级
- [`docs/agents/architecture.md`](../agents/architecture.md) —— 架构不变量与 tmux 管理器交互契约
