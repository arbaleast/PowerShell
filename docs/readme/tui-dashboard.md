# 🖥️ tmux 管理器 TUI 仪表盘

本文记录 `sss`（[`Start-TmuxSession`](../../ShellPrompt/Public/Start-TmuxSession.ps1)）tmux 管理器仪表盘的**结构与交互契约**。

---

## 一、当前状态

`sss` 的仪表盘现在有**两条轨**：

| 轨 | 渲染实现 | 开关 | 状态 |
|---|---|---|---|
| **Terminal.Gui 轨**（默认） | **独立的 Terminal.Gui v2 应用**（`Show-TmuxTuiDashboard`） | `UI.DashboardTuiEnabled = $true`（默认） | 当前主线 |
| **PSTui GridView 轨**（回退） | 仓库自有单行工具条 + PSTui `Out-ConsoleGridView` | `UI.DashboardTuiEnabled = $false` | **回退轨**，保留到阶段 C 真机验收通过 |

- Terminal.Gui 轨是**独立应用**，不是"套了 Terminal.Gui 装饰的 GridView"：Terminal.Gui 自己负责布局、绘制、表格、选择、键盘、缩放与状态栏；仓库既有的 PowerShell 业务层（`Invoke-TmuxSessionFetch` / `Get-TmuxSessionState` / `Invoke-TmuxAttach` / `New-TmuxSession` / `Invoke-TmuxSessionDeletion` / `Invoke-SshCommand`）继续负责 SSH 与 tmux，**Terminal.Gui 不重写任何 SSH/tmux 逻辑**。
- PSTui 链路、`Invoke-GridViewPrompt` 与 SSH 主机选择器（[`Show-HostSelector`](../../ShellPrompt/Private/Show-HostSelector.ps1)）**都保留**；主机选择器仍是 PSTui 表格，不在本次迁移范围内。
- GridView 轨的其它 `Out-ConsoleGridView` 能力（全局操作菜单等）不迁移。

下文第二章描述 Terminal.Gui 轨，第三章描述回退轨（GridView）。

---

## 二、Terminal.Gui 轨

### 2.1 程序集加载

Terminal.Gui 从仓库内置的 vendored 程序集加载：

- 载入源：`Modules/PSTui/<最高版本目录>/Terminal.Gui.dll`（版本钉 **2.4.10.0**）。
- 载入方式：**独立可回收 `AssemblyLoadContext`**（[`Get-TguiContext`](../../ShellPrompt/Private/Get-TguiContext.ps1)），带路径解析回调连带加载同目录依赖（`System.IO.Abstractions` / `Wcwidth` / `ColorHelper`）。
- 该上下文是**幂等**的：首次调用加载并缓存，后续复用；依赖或程序集缺失时抛可定位的终止错误，不静默降级。

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
- `X` 删除走 `Invoke-TmuxSessionDeletion` / `Remove-TmuxSession`，**二次确认在业务函数内**，本层不复刻确认逻辑（防拆这道防误删闸）。
- 动作值仍以 `Get-TmuxActionDefinition` 为**唯一事实来源**，与回退轨的动作契约一致。

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

| 键 | 默认值 | 作用 |
|----|--------|------|
| `UI.DashboardTuiEnabled` | `$true` | `$true` 走 Terminal.Gui 轨；`$false` 回退到 PSTui GridView 轨 |
| `UI.DashboardFullScreen` | `$true` | **仅回退轨**：控制 GridView 仪表盘的全屏标志 |

> `UI` 域是 `[ordered] OrderedDictionary`，条目**不是 PowerShell 属性**：判键存在要用 `.Contains('X')`，取值用 `['X']`——用 `.PSObject.Properties['X']` 判存在恒为 `$null`，开关会永远不生效。

### 2.8 非交互终端护栏

输入或输出被重定向（管道 / CI）时，Terminal.Gui 的 `Init` **不会抛异常**，但事件循环会永久阻塞。因此仪表盘在触碰 TG 之前先判定 `[Console]::IsInputRedirected` / `[Console]::IsOutputRedirected`，命中则直接跳过并返回。

### 2.9 配色契约（ALC 原生主题）

**Terminal.Gui 轨必须自带一套主题装配**，不能沿用 PSTui 轨的 `Set-TgColorScheme`：

| 事项 | 事实 |
|------|------|
| 载入方式不同 | PSTui 轨经 `Add-Type` 走**默认加载上下文**；仪表盘轨走**独立 ALC**（§2.1）。同名类型跨程序集是**两套类型身份**，互相赋值抛 `Cannot convert ... Scheme to ... Scheme` |
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
| Terminal.Gui 版本 | **2.4.10.0**，vendored 于 `Modules/PSTui/1.0.5/Terminal.Gui.dll`（**已入版本库**，版本固定） |
| PSTui 版本 | 1.0.5（保留，见第三章） |
| 模块导入耗时 | ≈ **207 ms**（冷导入，`-NoProfile`） |
| 导入后是否已加载 TG/PSTui | **否** —— 惰性加载，模块导入**不**给 Shell 启动增加负担 |
| `Get-TguiContext` 首次 / 二次 | **28.9 ms** / **1.2 ms**（ALC 与 TG 反射句柄有缓存） |
| 仪表盘窗口组装 | 首次 ≈ **840 ms**（TG 静态初始化 + JIT，一次性），稳态 ≈ **30–45 ms** |
| CI 触发路径 | `ShellPrompt/**`、`Microsoft.PowerShell_profile.ps1`、workflow 本身 —— ⚠️ **尚未含 `Modules/**`**：vendored 依赖（`Modules/PSTui/1.0.5/Terminal.Gui.dll` 等）变更同样会改变仪表盘行为，但当前推送凭据无 `workflow` scope，改不了 `.github/workflows/test.yml`，待补 |

---

## 三、回退轨：PSTui GridView（`UI.DashboardTuiEnabled = $false`）

> 本章描述的是**回退轨**，保留到阶段 C 真机验收通过为止。以下内容仍然有效且可达。

### 3.1 分层

| 层 | 职责 | 判定标准 |
|---|---|---|
| **数据层** | 把"远端到底发生了什么"变成**可判定的状态对象**：有会话 / 确实没会话 / 探测失败，以及失败时的稳定错误码 | 不碰控制台、不读配置、不做 UI 决策 |
| **渲染层** | 把状态对象变成**屏幕上的一行/一屏**：主视图（表格或占位面板）与单行工具条 | 不发起网络请求、不做动作分发 |
| **交互层** | 把"用户按了什么"变成**一个动作值**：单键读取 → 键位映射 → 事件循环 | 不区分"成功 / 失败"，只区分"登记过的键 / 没登记的键" |

分层的直接收益：键位契约（哪个键做什么）、失败判定（什么算失败）、渲染外观（长什么样）三者各自只有一个事实来源，互不牵连。

### 3.2 回退轨的文件一览

**数据层**

| 文件 | 职责 |
|---|---|
| [`Get-TmuxSessionState.ps1`](../../ShellPrompt/Private/Get-TmuxSessionState.ps1) | 把探测结果归一成状态对象，并提供稳定错误码映射（`Get-TmuxErrorCode`） |
| [`Get-TmuxPlaceholderRow.ps1`](../../ShellPrompt/Private/Get-TmuxPlaceholderRow.ps1) | 构造占位面板行，列名与 `Get-TmuxSessionGridRow` 完全一致 |
| [`Invoke-TmuxSessionFetch.ps1`](../../ShellPrompt/Private/Invoke-TmuxSessionFetch.ps1) | SSH 探测入口：后台线程执行 `Get-TmuxSessions -Force`，后台不可用时退回同步调用 |
| [`Submit-TmuxBackgroundTask.ps1`](../../ShellPrompt/Private/Submit-TmuxBackgroundTask.ps1) | 后台线程任务**提交端**：`Start-ThreadJob` + 按 `-DependencyFile` dot-source 依赖 |
| [`Receive-TmuxBackgroundTask.ps1`](../../ShellPrompt/Private/Receive-TmuxBackgroundTask.ps1) | 后台线程任务**收割端**：等待完成，把成功/超时/作业内异常归一成统一形状 |
| [`Submit-WttrPrefetch.ps1`](../../ShellPrompt/Private/Submit-WttrPrefetch.ps1) | 标题区天气的后台预取与缓存回写 |

**渲染层**

| 文件 | 职责 |
|---|---|
| [`Format-TmuxToolbarText.ps1`](../../ShellPrompt/Private/Format-TmuxToolbarText.ps1) | 把动作集合渲染成**一行**工具条文本 |
| [`Show-TmuxSessionDashboard.ps1`](../../ShellPrompt/Private/Show-TmuxSessionDashboard.ps1) | 唯一主视图：有会话时渲染会话表格，失败/空态渲染占位面板 |

**交互层**

| 文件 | 职责 |
|---|---|
| [`Get-TmuxActionDefinition.ps1`](../../ShellPrompt/Private/Get-TmuxActionDefinition.ps1) | 键位契约的**唯一事实来源**：键 → 文案 → 动作值 → 是否依赖会话 |
| [`Resolve-TmuxActionKey.ps1`](../../ShellPrompt/Private/Resolve-TmuxActionKey.ps1) | 纯函数：单键 → 动作值；未登记的键返回空串 |
| [`Read-TmuxActionKey.ps1`](../../ShellPrompt/Private/Read-TmuxActionKey.ps1) | 用 `[Console]::ReadKey($true)` 读**一个**键并归一化成 token；带 `-KeyReader` 注入口供测试注入 |
| [`Show-TmuxActionBar.ps1`](../../ShellPrompt/Private/Show-TmuxActionBar.ps1) | 底部单行状态栏 + 单键事件循环 |

**已删除**：`Private/Show-SessionManager.ps1`（全局操作菜单）、`Private/Get-GridViewManagerRow.ps1`、`Private/Write-TmuxAvailabilityNotice.ps1`；`Invoke-GridViewSessionManager` 已从 [`Invoke-GridViewMenu.ps1`](../../ShellPrompt/Private/Invoke-GridViewMenu.ps1) 中移除；`Show-TmuxSessionList`（删除流程的会话列表）保留不变。

### 3.3 布局与动作条

正常态（`Status = Ok`）：

```text
┌──────────────────────────────────────────────────────────────────────────┐
│ TMUX 管理器 [debian] - 会话 2 (附 1 / 分 1)                               │
│            [a]附着  [n]新建  [r]刷新  [s]SSH  [x]删除  [q]退出           │ ← 单行工具条
├──────────────────────────────────────────────────────────────────────────┤     （拼进窗口标题）
│ No   Session          State         Windows                              │
│ 01   tmux-100001      ● 已附着            2                              │
│ 02   tmux-100002      ○ 已分离            1                              │
├──────────────────────────────────────────────────────────────────────────┤
│ Rows: 2 | Enter Accept | Esc Close                                       │ ← PSTui 自带状态栏
└──────────────────────────────────────────────────────────────────────────┘
[TMUX] [a]附着  [n]新建  [r]刷新  [s]SSH  [x]删除  [q]退出 >                ← 底部单行动作条
```

失败态（`Status = Error`）：

```text
┌──────────────────────────────────────────────────────────────────────────┐
│ TMUX 管理器 [debian] - E_SSH_TIMEOUT                                     │
│            [n]新建  [r]重试  [s]直连  [q]退出                           │ ← 失败态文案
├──────────────────────────────────────────────────────────────────────────┤
│ No   Session                                          State              │
│      SSH 连接超时, 未能获取 tmux 会话列表   E_SSH_TIMEOUT · 按 r 重试 · 按 s 直连 SSH │
├──────────────────────────────────────────────────────────────────────────┤
│ Rows: 1 | Enter Accept | Esc Close                                       │
└──────────────────────────────────────────────────────────────────────────┘
[TMUX] [n]新建  [r]重试  [s]直连  [q]退出 >
```

三处关键点：

1. **工具条在标题里**：表格打开期间键位也可见，用户不必猜。
2. **占位面板与正常态共用面板**：失败时屏幕上是"一行说明 + 一个错误码 + 一条降级指引"，而不是留白。占位行的 `Value` 为**空串**——这是契约，主视图据此判定"用户选中的不是会话"，转而进入动作条，而不是误把说明行当成会话名去附着。
3. **动作条在表格之下**：表格内 `Esc` 进入动作条，动作条 `Esc` 退出管理器——与旧流程"列表 ESC → 菜单 ESC → 退出"的肌肉记忆一致。

### 3.4 回退轨的键位速查表

| 键 | 动作值 | 动作 | 需要会话 | 正常态文案 | 失败态文案 |
|----|--------|------|----------|------------|------------|
| `a` | `Attach` | 附着/恢复会话 | **是** | `[a]附着` | `[a]附着` |
| `n` | `New` | 新建 tmux 会话 | 否 | `[n]新建` | `[n]新建` |
| `r` | `Refresh` | 刷新会话列表 | 否 | `[r]刷新` | `[r]重试` |
| `s` | `Ssh` | 直连 SSH | 否 | `[s]SSH` | `[s]直连` |
| `x` | `Remove` | 删除会话（高危，二次确认在 `Remove-TmuxSession` 内） | **是** | `[x]删除` | `[x]删除` |
| `q` | `Quit` | 退出管理器 | 否 | `[q]退出` | `[q]退出` |

补充规则：

- **无会话时不暴露** `a`（附着）与 `x`（删除），避免出现"点了没反应"的死键；界面与行为保持一致。
- **`Context` 只切换文案，不切换键位**：`r` 在任何状态下都是刷新/重试，`s` 在任何状态下都是 SSH/直连。用户的肌肉记忆不因状态切换而失效。
- **未登记的键**在动作条里提示一次并继续等待（最多 `-MaxAttempts` 次，默认 10）。
- **`ESC` 退出管理器**；**无输入**（非交互终端 / Ctrl-C / 读取失败）按"用户退出"处理。
- **表格内**：`↑↓` 选择，`Enter` 附着/恢复所选会话，`Esc` 进入底部动作条。

### 3.5 回退轨的渲染约束

- 唯一渲染实现仍是 [`Invoke-GridViewPrompt`](../../ShellPrompt/Private/Invoke-GridViewMenu.ps1) → PSTui `Out-ConsoleGridView`。主视图的正常态与失败态走**同一条**渲染路径（占位行的列名与正常行完全一致）。
- **未对 Terminal.Gui 做任何反射**：`TableView.Style` / `ColumnStyle.Width` 等 readonly 字段仍是仓库明令禁止改动的区域（见 [`docs/agents/architecture.md`](../agents/architecture.md)）。
- 底部动作条是**纯控制台输出**（`Write-Host` 单行文本），不是表格视图。它的内联 ANSI 在控制台里真实生效，因此「删除」项可以染成危险色。
- 主轨可用性把关点不变：`Show-TmuxSessionDashboard` 入口仍统一执行 `Assert-ConsoleUiReady -Feature 'tmux 会话主视图'`，主轨不可用时抛可定位的终止错误，不静默降级。

### 3.6 异步刷新会话列表

回退轨首屏不串行等网络：SSH 探测与标题区 wttr.in 天气都放在**后台线程并行**进行，主线程只在需要结果的那一刻收割。

- **提交端** `Submit-TmuxBackgroundTask` 用 `Start-ThreadJob` 跑脚本块。线程作业运行在**独立 runspace**，拿不到模块作用域里的私有函数，因此依赖必须显式列出（`-DependencyFile`）——这是硬约束，不是可选项。
- **收割端** `Receive-TmuxBackgroundTask` 把成功/超时/作业内异常归一成统一形状；超时或失败**不会向调用方冒泡**。
- `Invoke-TmuxSessionFetch` 的三条降级路径（提交失败 / 作业内异常 / 等待超时）**全部退回同步** `Get-TmuxSessions`。后台不可用只影响"快慢"，不影响"准不准"。
- 天气预取失败静默降级，绝不阻塞首屏。

### 3.7 回退轨的屏幕生命周期

- `Enter-TmuxAlternateScreen` / `Exit-TmuxAlternateScreen`（幂等，状态位 `$script:TmuxAltScreenActive` 守护）包裹 `Start-TmuxSession` 整个 while 主循环，`finally` 恒发 `\e[?1049l`——退出管理器 / 异常 / Ctrl-C 都还原 Shell 现场。
- **全屏子动作暂停/恢复**：attach、`n` 新建、`s` 直连 SSH 三条会接入全屏 tmux / ssh 的路径在执行前 `Exit` → 执行后 `Enter`，让 tmux 拿到干净画面，detach 后回到管理器备用屏。
- **绝对坐标重绘**：每轮迭代开头 `Clear-TmuxScreen`（`[Console]::Clear()` + `[Console]::SetCursorPosition(0, 0)`）全量重绘；常驻画面（标题 Y=0 / 动作条 Y=$h-1 / Input 底栏）用绝对坐标定位，不跟随光标下沉。
- **输入态状态机**：Normal 态维持单键直达；Input 态（新建会话名）只处理 `Enter` / `Esc` / `Backspace` / 可打印字符，其余按键静默忽略——`Read-TmuxActionKey` 把控制字符归一为 `IGNORE` 哨兵，动作条对 `IGNORE` 静默 continue，**绝不打印"未识别的按键"**。
- **Esc 取消零翻转**：全屏交接放在 `New-TmuxSession` 内部（SSH 启动前 `Exit`、退出后 `Enter`），取消路径不产生屏幕翻转。

---

## 四、错误码表

| 错误码 | 含义 | 判定依据 | 用户指引 |
|--------|------|----------|----------|
| `E_SSH_TIMEOUT` | SSH 等待超时（作业被 Kill），与"远端命令失败"是两回事 | 探测结果标记超时 | 按 `r` 重试 · 按 `s` 直连 SSH |
| `E_SSH_UNREACHABLE` | 网络不可达 / 端口被拒绝 / DNS 失败 | 探测结果标记网络错误 | 按 `r` 重试 · 按 `s` 直连 SSH |
| `E_SSH_AUTH` | SSH 认证或主机密钥校验失败 | 错误文本命中认证关键字（如 `Permission denied` / `Host key verification failed`） | 按 `r` 重试 · 按 `s` 直连 SSH |
| `E_SSH_FAILED` | SSH 进程或远端命令失败（退出码非 0） | 退出码非 0 | 按 `r` 重试 · 按 `s` 直连 SSH |
| `E_NO_TMUX` | 命令跑通了但拿不到 tmux 版本（远端未安装 tmux / tmux server 未运行） | 退出码 0 且无版本信息 | 按 `r` 重试 · 按 `s` 直连 SSH |
| `E_UNKNOWN` | 没有任何探测信息（兜底，理论不可达） | 探测结果为空 | 按 `r` 重试 · 按 `s` 直连 SSH |

错误码在**回退轨**出现在占位面板的 `State` 列（`错误码 · 降级指引`）与主视图标题的状态摘要；在 **Terminal.Gui 轨**只出现在顶部辅助行。

---

## 五、已知限制 / 尚未验证

- **真机发现的"只剩边框、内容全无"已定位并修复（2026-10-30，待复验）**：真机首验反馈仪表盘只画边框、文本全无。共定位到**两个叠加根因**：
  1. **配色**：Terminal.Gui 内置 `Base` 方案 `Normal` 是白对白（前景 = 背景 = `(255,255,255)`），而仪表盘轨从未套用仓库主题 ⇒ 文字隐形。修复见 §2.9（ALC 原生 `Set-TguiTheme` + 可见性兜底 `Resolve-TguiScheme`）。
  2. **事件循环**（更根本）：编排层调的是**泛型** `Application.Run<Window>(handler, driver)`，该重载内部会 **new 一个全新的空 Window** 来跑 —— 组装好的仪表盘**从未上屏**，空窗只画边框，故表现为"只剩边框"。修复见 §2.10（改用非泛型 `Run(IRunnable, Func)` 并传入组装好的窗口实例）。

  **以上两处修复均尚未在 Windows Terminal 上复验。**
- **未在真机验证**：Terminal.Gui 轨的实现与测试是在 **Linux + 无头（headless）Terminal.Gui** 环境下产出的；**Windows Terminal + PowerShell 7.6 的真机行为尚未验证**（容器内 PTY 分配被禁，无法做真终端端到端回归）。
- **阶段 C 清单待人工执行**：真机验收清单**仍需由人在 Windows 上跑一遍**（含备用屏进出、Ctrl+C 还原、resize 重排、附着/新建/直连全屏交接、删除二次确认）。
- **回退轨尚未移除**：`UI.DashboardTuiEnabled = $false` 的 PSTui GridView 轨在阶段 C 验收通过前**继续保留**；两轨并存期间，行为差异（键位、错误呈现、屏幕生命周期）以本文第二章与第三章分别描述为准。
- **终端宽度下限 40 列**：仪表盘按 **40×10** 起步（`New-TmuxTuiDashboardWindow` 的 `ValidateRange` 与编排层的屏幕夹取一致）。真实终端窄于 40 列时，仪表盘会按 40 列布局 ⇒ **该极端场景存在横向溢出**。宽度 ≥ 72 列起隐藏 WINDOWS 列、≥ 96 列起隐藏 STATUS 列（见 §2.4），这三档目标尺寸（100×30 / 120×35 / 160×45）不受影响。
- **首次拉起的一次性延迟**：首次进入 `sss` 时 Terminal.Gui 静态初始化 + JIT 约 **0.84 s**（之后稳态 30–45 ms）；模块导入阶段**不**加载 Terminal.Gui/PSTui（惰性），因此不影响 Shell 启动耗时。详见 §2.12。
- **绘制级断言无法无头执行**：Terminal.Gui 2.4.10 未暴露 `FakeDriver` / 公开的 `View.Render`，无法在无头环境捕获"实际画出的像素"。本地证据止于方案配色值、布局几何、IL 反汇编与 `IsRunning` 行为探针；**"内容确实可见"只能由真机清单第 0 项确认**。

### 真机验收清单（Windows Terminal + pwsh 7.6+，逐项打勾）

准备：真机置 `UI.DashboardTuiEnabled = $true`（默认），对一台真实 tmux 主机运行 `sss`。

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

登记结果时注明日期与窗口宿主（Windows Terminal / conhost），任一项不过按文档第三章回退到 `UI.DashboardTuiEnabled = $false` 上报。

---

## 相关文档

- [交互菜单后端（PSTui GridView 单轨）](gridview-menus.md) —— 菜单能力边界、配色槽位、刷新语义
- [架构](architecture.md) —— 模块目录树与加载流程
- [命令一览](commands.md) —— 公开命令与交互流程
- [配置](configuration.md) —— 配置域与优先级
- [`docs/agents/architecture.md`](../agents/architecture.md) —— 架构不变量与 tmux 管理器交互契约
