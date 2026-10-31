# 🖥️ tmux 管理器 TUI 仪表盘

本文记录 `sss`（[`Start-TmuxSession`](../../ShellPrompt/Public/Start-TmuxSession.ps1)）tmux 管理器仪表盘的**结构与交互契约**。

---

## 一、当前状态

`sss`（tmux 管理器）和 SSH 主机选择器共用同一套 Terminal.Gui v2 交互界面，**只有一条渲染轨**，没有可切换的第二套实现或渲染开关。

- **Terminal.Gui v2 负责 UI**：布局、绘制、表格、选择、键盘、缩放和备用屏全部由 Terminal.Gui 管理。
- **PowerShell 业务层负责数据与连接**：SSH config 读取、远端 tmux 探测、附着/新建/删除、SSH 直连等仍由模块内的业务函数完成，Terminal.Gui 不重写任何 SSH / tmux 逻辑。
- **SSH 主机选择（2026-10-31 重构）**：由 `Show-HostSelector` 分发到 `Show-SshHostDashboard` → `Invoke-SshHostDashboard`，呈现为**多区域 SSH 主机仪表盘**（顶部分类导航 / 左侧主机列表 / 右侧详情卡片 / 底部快捷键栏），结构与键位契约见本文 **§2.13**。旧单表格实现（`Invoke-TguiHostSelector`）**保留可用但不是默认路径**。
- 交互式界面依赖的 Terminal.Gui 程序集随仓库提供（`Modules/Terminal.Gui/<ver>/`），无需用户单独安装。

下文第二章描述仪表盘与主机选择器的运行契约（§2.13 为 SSH 主机仪表盘专章），第三章说明 vendored 依赖的归属与升级方式。**面向使用者的操作说明**见 [功能特点](features.md)。

---

## 二、Terminal.Gui 轨

### 2.1 程序集加载

Terminal.Gui 从仓库内置的 vendored 程序集加载：

- 载入源：`Modules/Terminal.Gui/<最高版本目录>/Terminal.Gui.dll`（版本钉 **2.4.10.0**，全仓库单副本）。
- 载入方式：**独立且不可回收的 `AssemblyLoadContext`**（[`Get-TguiContext`](../../ShellPrompt/Private/Get-TguiContext.ps1)），带路径解析回调连带加载同目录依赖（`System.IO.Abstractions` / `Wcwidth` / `ColorHelper`）。该上下文生命周期与进程一致：首次调用加载并缓存到 `$script:TguiContext`，后续复用，全仓库没有 `Unload` 调用。**不要改回可回收 ALC**——旧上下文被 GC 回收后，依赖解析可能命中已卸载的 ALC 并抛 `AssemblyLoadContext is unloading or was already unloaded`。
- 依赖或程序集缺失时抛可定位的终止错误，不静默降级。
- Terminal.Gui 的 **vendored 归属**（是否拆成独立依赖目录、版本如何管）见 [第三章](#三vendored-依赖归属)。

> 本文涉及的 Terminal.Gui API 行为均来自对 vendored **2.4.10.0** 的反射探针实测，**不是按文档示例假定**。探针脚本属于一次性诊断产物，不随仓库分发。

### 2.2 屏幕布局

整窗由 [`New-TmuxTuiDashboardWindow`](../../ShellPrompt/Private/New-TmuxTuiDashboardWindow.ps1) 组装（**2026-10-31 视觉层次升级**）：

```text
ShellPrompt TMUX Manager · 主机 deb                          已连接   ← 标题带(左=标识 / 右=状态徽标)
会话: 3 · Attached: 1 · Detached: 2                                     ← 统计行
                                                                    ← 状态标题行(空态/错误态才有内容)
┌────┬──────────────────────────────────────────────────────┬──────────┬─────────┐
│No  │SESSION                                               │  STATUS  │  WINDOWS│ ← 会话表
├────┼──────────────────────────────────────────────────────┼──────────┼─────────┤
│1   │work-main                                             │ Attached │        4│
│2   │副业-android构建                                       │ Detached │        6│
└────┴──────────────────────────────────────────────────────┴──────────┴─────────┘
 Enter  附着 │ n  新建 │ r  刷新 │ s  SSH │ x  删除 │ q  退出 │ Esc  退出   ← 快捷键栏
```

> 空态 / 错误态：会话表整块**不画**，主体区只剩一行**居中**指引
> （`n 新建 · r 刷新 · s 直连` / `r 重试 · s 直连`），状态标题行给出标题或错误码。

- **顶部状态区固定 3 行**：
  - **标题带**拆成**左右两片不重叠的 Label**：左半 = 产品标识 + 主机（按可用宽度取长/中/短形态），右半 = **连接状态徽标**（右对齐，`已连接` / `连接失败`）。两者宽度由状态文案宽反推，**窄终端下标题不会把状态挤掉**。
  - **统计行** = `会话: N · Attached: N · Detached: N`。
  - **状态标题行**仅在**空态**（`远端当前没有 tmux 会话`）或**错误态**（`连接失败 · <错误码> · <原因>`）有内容；正常态留空。
- **中间是会话表**，列固定为 `# | SESSION | STATUS | WINDOWS`：`STATUS` **居中**、`WINDOWS` **右对齐**；`SESSION` **吃满剩余宽度**（列宽计划见 [`New-TmuxTuiColumnPlan`](../../ShellPrompt/Private/New-TmuxTuiColumnPlan.ps1)）。
  - 列宽几何：`表格总宽 = Σ(各列宽) + (可见列数 + 1)`（可见列数-1 个列间竖线 + 左右两条边框边）。据此 `SESSION` 取 `终端宽 − 其余可见列宽 − (可见列数 + 1)`，列宽之和**恰好等于终端宽**——表格既不横向溢出也不留空洞。
  - `TableStyle.ExpandLastColumn = $false`：否则 TG 会把**末列**（`WINDOWS`）拉伸成吃掉全部余量的巨型空列。
  - **`SESSION` 列宽上限 100**（TG 的 `TableView.MaxCellWidth` 默认值，2026-10-31 真机取证）：终端宽于 **128 列**时 `SESSION` 封顶 100、表格保持 128 宽，右侧留白。
    > ⚠️ **不要调大 `MaxCellWidth`**：实测设成 102 / 132 后，TG 2.4.10 的 `TableView` 在**布局阶段死循环**（PTY 里 40 秒只吐 `[1;1H[?25l`，事件循环根本起不来）——这是 TG 上游限制，只能在**列宽计划侧**封顶，计划与渲染因此保持一致。
- **空态 / 错误态不再画空表格框**：表格 `Visible = $false`，主体区改为**居中**的一行可执行指引（文案由 `Get-TmuxActionDefinition` 生成，与底部快捷键栏同源同形）。
- **底部是固定快捷键栏**（Terminal.Gui `StatusBar` + `Shortcut`），贴底一行。
  渲染契约(2026-10-30 真机+子视图取证)：TG 2.4.10 的 `Shortcut` 屏幕渲染序 = **键名 → HelpText → Title**，
  故工厂层 `Title = 纯标签`、`HelpText = ''` —— HelpText 再放标签会把"键 标签"渲染两遍。
- 窗口 `BorderStyle` 置空：置空后窗口内容区等于整个 Frame，绝对行号才与屏幕行号对齐。

### 2.3 状态分型

视图模型由 [`ConvertTo-TmuxTuiViewModel`](../../ShellPrompt/Private/ConvertTo-TmuxTuiViewModel.ps1) 一次成型，分三态：

| 模式 | 触发条件 | 表现 |
|---|---|---|
| `Session` | 探测成功且确有会话 | 会话表正常渲染，状态标题行留空，居中指引为空 |
| `Empty` | 探测成功但确实没有会话 | **表格隐藏**，状态标题行给 `远端当前没有 tmux 会话`，主体区居中给操作提示（如 `n 新建 · r 刷新 · s 直连`） |
| `Error` | 探测失败 | **表格隐藏**，状态标题行给 `连接失败 · <错误码> · <原因>`，主体区居中给操作提示（如 `r 重试 · s 直连`） |

两条硬约束：

1. **错误码与长错误文本绝不进会话表行**——它们只出现在状态标题行。空态与错误态也**不伪造占位行**。
2. **空态与错误态严格区分**：探测失败永远不会显示成"没有会话"（错误码由 `Get-TmuxErrorCode` 给出，取值与含义见第五章错误码表）。

> 状态**不靠颜色单独表意**：连接状态徽标的文案本身就写着"已连接 / 连接失败"，错误码也直接写进标题行；颜色只是第二重强化（绿 / 红）。

### 2.4 键位

底部快捷键栏（[`New-TmuxTuiShortcutList`](../../ShellPrompt/Private/New-TmuxTuiShortcutList.ps1)）：

| 键 | 动作 | 需要会话 | 说明 |
|----|------|----------|------|
| `Enter` | 附着/恢复选中会话 | **是** | 无会话时**不出现** |
| `N` | 新建 tmux 会话 | 否 | |
| `R` | 刷新会话列表 | 否 | |
| `S` | 直连 SSH | 否 | |
| `X` | 删除选中会话 | **是** | 无会话时显示为 `X 删除 (不可用)`（不绑定键位） |
| `Q` | 退出管理器 | 否 | |
| `Esc` | 退出管理器 | 否 | 走 Terminal.Gui 内建 Quit 路径（见 2.6） |

- 无会话时**附着项不绑定也不出现**，**删除项不绑定、且明确标注 `(不可用)`**——不可用状态是显式展示，不是静默隐藏。
- `X` 删除走 `Invoke-TmuxSessionDeletion`，**二次确认在业务函数内**，本层不复刻确认逻辑（防拆这道防误删闸）。
- 动作值以 `Get-TmuxActionDefinition` 为**唯一事实来源**（快捷键栏工厂直接消费它），UI 层不另立一份键位表。

**按宽度取舍显示项（2026-10-31）**：TG 的 `StatusBar` **不会换行**，放不下就在右端**硬截断**（真机 40×10 取证：`s SSH` 被截成 `s SS`，`X`/`Q`/`Esc` 三项完全不可见——用户既不知道能删除，也不知道怎么退出）。因此快捷键栏工厂按**可用列宽预算**挑选要显示的项：

- 宽度口径（120×35 **原始转义流**取证）：TG 的 `StatusBar` 逐项渲染 `[键名]["  "][标签][" │ "]`，**末项的分隔段被裁掉**，故
  `总宽 = 1(前导空格) + Σ(键名宽 + 2 + 标签宽) + 3 × (项数 - 1)`，实测 120 列终端 7 项 = 73 列。
  实现按 **键名+标签+5** 逐项累加（比实测口径多算 3 列）——**宁可少显示一项，也不让底栏出现半截文本**（真机 60 列实测：多算一项就把末项标签截成 `q 退`）。
- 选取优先级：`Enter 附着` > `n 新建` > **`q 退出`** > `r 刷新` > `s SSH` > `x 删除` > `Esc 退出`。
  **"退出"排在"刷新"之前**——用户看不到怎么退出是不可接受的；`Esc` 是与 `Q` 同义的纯展示项，最先被舍掉。
- **取舍只影响"显示哪几项"，键位语义完全不变**：未被选中的项按键依然生效（只是不显示）。
- 终端 < 96 列时可能只剩 3 项（`Enter` / `n` / `q`），这是有意的取舍，而非截断。

> 文案随状态切换：`Context = 'Error'` 时 `r` 显示为"重试"、`s` 显示为"直连"（键位与动作值恒定），与状态标题行、居中指引同一套来源。

### 2.5 终端所有权（关键规则）

Terminal.Gui 轨里，**Terminal.Gui 是终端的唯一所有者**：

- Terminal.Gui 自己管理备用屏（`ESC[?1049h` / `ESC[?1049l`）。
- 仓库自有的 `Enter-TmuxAlternateScreen` / `Exit-TmuxAlternateScreen` 在该轨下通过 `$script:TmuxTerminalOwner = 'Tgui'` **整体静音**，因此**只有一层备用屏**，不会出现双层嵌套。
- `Application.Shutdown()` 负责还原光标 / 鼠标 / 粘贴 / 备用屏；**正常退出、Ctrl+C 与异常路径**都会走到。
- 驱动名固定为 **`'ansi'`**：`DriverRegistry` 只注册 `'windows'` / `'dotnet'` / `'ansi'` 三个驱动，而 `'dotnet'` 驱动的输入层**无视 `AppModel` 无条件发备用屏序列**，`'ansi'` 驱动才让 `AppModel` 生效——固定 `'ansi'` 才能保证“TG 独占终端”在 Windows Terminal 与其它支持 ANSI 的终端上行为一致。
- 附着 / 新建 / 直连 SSH 这三个全屏业务子动作在 TG 事件循环**退出并 Shutdown 之后**才执行，执行完主循环重新 `Init`，天然恢复到仪表盘。

### 2.6 键盘与缩放

Terminal.Gui 2.4.10 上踩过并固化的三条规则：

1. **`Shortcut.BindKeyToApplication` 必须置 `$true`**：默认 `$false` 时 Shortcut 只登记进自己的键表，应用级键表里没有它，真实按键永远到不了 `Action`——状态栏会退化成纯展示件。
2. **`Shortcut.Command` 必须保持 `NotBound`**：若同时设成 `Accept`，会形成 `InvokeCommandsBoundToKey → RaiseActivated → DefaultHotKeyHandler → InvokeCommands → InvokeCommandsBoundToKey` 的死循环，**StackOverflow 崩进程**。
3. **`Esc` 不由仪表盘绑定**：应用级键表默认已绑定 `Esc → Quit`，重复登记会抛 `A binding for Esc exists`。因此 `Esc` 退出走 Terminal.Gui 内建的 Quit 路径，快捷键栏里的 `Esc` 项只承担**展示**职责；编排层把"事件循环返回且无待处理动作"一律判定为用户主动退出。

**缩放**：表格高度用 `Dim.Fill(Dim.Absolute(1))`、快捷键栏用 `Pos.AnchorEnd()`，因此终端尺寸变化时布局**自动重排**，表格与快捷键栏之间**零重叠、零空档**。`Application.ScreenChanged` 触发重建，**列计划按新宽度重算**——窄窗口下**次要列自动隐藏**（`STATUS` 在终端 < 96 列时隐藏，`WINDOWS` 在 < 72 列时隐藏）。

**建窗尺寸的来源（2026-10-31 修正）**：尺寸解析收敛到 [`Get-TguiTerminalSize`](../../ShellPrompt/Private/Get-TguiTerminalSize.ps1)，按可信度依次尝试：

| 优先级 | 来源 | 说明 |
|---|---|---|
| 1 | `$global:TguiScreenW/H`（`ScreenChanged` 事件报数） | 上一轮的真实尺寸，最权威 |
| 2 | `[Console]::WindowWidth/Height` | **终端自己的尺寸**，`Init` 之前即可读 |
| 3 | TG 的 `Application.Screen` | 两者都拿不到时的兜底 |
| 4 | 缺省 `120×35` | 最后兜底；最终按 **40×10** 夹取 |

> **为什么不能只信 `Application.Screen`**：TG 2.4.10 的 `'ansi'` 驱动在 `Init` 之后、事件循环跑起来之前报 `0×0`——它要等终端回应 `CSI 18t`（查询窗口尺寸），而那个应答是**异步**到达的。实测（PTY 取证）：`[Console]::WindowWidth = 120` 但 `Application.Screen.Width = 0`，`ScreenChanged` 事件要**等到收到按键**才第一次报 `120×35`。旧实现因此按 `40×10` 兜底 → 列计划按 40 列算 → `STATUS`/`WINDOWS` 被当成"窄屏"隐藏 → **120 列的终端上会话状态完全看不见**。
> `Console` 排在 `Application.Screen` 之前还有一层原因：某些宿主下 TG 的 `Screen` 是**陈旧默认值**（重定向容器里实测 80×25），而终端自己的尺寸才是用户看到的宽度；两者不一致时事件会在下一轮把尺寸对齐。

**选中**：Terminal.Gui 2.4.10 的 `TableView` **没有** `SelectedRow` 属性，选中行读 `TableView.Value.SelectedCell.Y`；刷新后按**会话名**保留选中。`TableView.FullRowSelect = $true`：选中行**整行**高亮（而非只高亮单元格）。

### 2.7 配置

`UI` 域当前只剩 **`UI.Theme`**（TGUI 配色槽位，见 [`Private/Initialize-Config.ps1`](../../ShellPrompt/Private/Initialize-Config.ps1)）。

> 旧版 UI 回退开关（`UI.GridViewFocus` / `UI.GridViewFullScreen` / `UI.DashboardTuiEnabled` / `UI.DashboardFullScreen`）已被移除；这些键残留在 `config.ps1` 里没有效果（静默忽略），无害。

> `UI` 域是 `[ordered] OrderedDictionary`，条目**不是 PowerShell 属性**：判键存在要用 `.Contains('X')`，取值用 `['X']`——用 `.PSObject.Properties['X']` 判存在恒为 `$null`，开关会永远不生效。

### 2.8 非交互终端护栏

输入或输出被重定向（管道 / CI）时，Terminal.Gui 的 `Init` **不会抛异常**，但事件循环会永久阻塞。因此仪表盘在触碰 TG 之前先判定 `[Console]::IsInputRedirected` / `[Console]::IsOutputRedirected`，命中则直接跳过并返回。

### 2.9 配色契约（ALC 原生主题）

**Terminal.Gui 轨必须自带一套主题装配**：仪表盘和主机选择器都从独立 ALC 加载 Terminal.Gui，唯一配色路径是 ALC 原生的 [`Set-TguiTheme`](../../ShellPrompt/Private/Set-TguiTheme.ps1)。

| 事项 | 事实 |
|------|------|
| 载入方式不同 | 仪表盘与主机选择器走**独立 ALC**（§2.1），与默认加载上下文里的同名 Terminal.Gui 类型是**两套类型身份**，互相赋值抛 `Cannot convert ... Scheme to ... Scheme` |
| 内置 `Base` 方案不可见 | 实测 `SchemeManager.GetScheme('Base').Normal` = 前景 `(255,255,255)` / 背景 `(255,255,255)` —— **白对白，文字隐形**；`'ansi'` 驱动不做终端颜色探测，故该状态恒定 |
| 视图默认方案名不统一 | `Window → 'Base'`、`StatusBar → 'Menu'`、`Label` / `TableView → ''`（回退 `'Base'`） |

因此仪表盘轨用 [`Set-TguiTheme`](../../ShellPrompt/Private/Set-TguiTheme.ps1) 做 **ALC 原生**装配：

1. **就地覆写已存在的方案实例**（`SchemeManager.GetScheme(name)`）的槽位，槽位表沿用 `UI.Theme.Slots`；**不新增方案名、不写 `ThemeManager.Theme`**（该组合会打坏 `SchemeManager` 内部字典与 `Theme` 的对应关系）。
2. **逐槽位等值跳过**：TG 2.4.10 把与现值相同的 `Attribute` 再写一遍不是幂等 no-op，而是触发一次 Scheme 重建并把槽位打回内置默认（实测 4 轮交替翻转）。
3. **显式绑定方案**（2026-10-31 视觉层次升级后的分工）：`Window` / 统计行 / 状态标题行 / 居中指引 / 会话表 / **快捷键栏**绑 `Base`，**标题带**与**表头**绑 `Menu`，**连接状态徽标**绑 `Dialog`（失败态绑 TG 内置 `Error`）；绑定前用 `Test-TguiSchemeVisible` 过滤"前景 = 背景"的不可见方案，`Resolve-TguiScheme` 再按候选顺序挑第一个**可见**的实例——**界面绝不允许因为配色而空白**。
4. **差异化槽位**用 `UI.Theme.SchemeOverrides` 表达（**只覆写已存在方案的槽位，绝不新增方案名**）：`Menu.Focus` 专供**表头**（`Sky` 字 + `Surface1` 底），`Menu.Normal` 供**标题带**，`Dialog.Normal` 供**状态徽标**（亮绿）。
5. **SSH 主机选择器同步**：它的底栏也改绑 `Base`，两个屏幕的底栏观感一致（键名冰青 / 标签亮白），且不再受 `Menu` 差异化影响。

> **表头与选中行必须分开**：TG 2.4.10 的 `Focus` 槽位被"聚焦态列头"和"有焦点时的选中行"**共用**——旧实现里表头与选中行渲染**完全同色**（白字 + 亮黑底），选中行分不清表头。现在表头走 `Menu.Focus`（冰青字）、选中行走 `Base.Focus`（亮白字），前景色不同，一眼可分。
>
> **Label 只取方案的前景色**（真机取证：`Menu.Normal.Bg` 设成 `Surface0` 时，标题行底色仍是窗口黑底）——所以标题带的层次靠**前景色**（冰青 vs 正文亮白）实现，不靠"整条染色带"。真正能整块着色的只有表格自身的单元格（表头 `Menu.Focus` 的底色）。

**16 色终端的量化约束（2026-10-31 实测）**：TG 的 `'ansi'` 驱动**只发 16 色 ANSI 码**，主题里的 RGB 会被**量化**到最接近的 16 色锚点（`Color.Colors16`，纯 RGB 欧氏距离）。实测：

| 主题 RGB | 实际落点 | 备注 |
|---|---|---|
| `(137,220,235)` Sky | `96` 亮青 | 标题带 / 表头 / 底栏键名 |
| `(205,214,244)` 正文 | `97` 亮白 | 正文 / 底栏标签 |
| `(255,255,255)` + `(69,71,90)` | `97` 亮白 + `100` 亮黑底 | 选中行 |
| `(69,71,90)` 底 | `100` 亮黑底 | 表头带 / 选中行底 |
| `(166,227,161)` Mocha 绿 | **`93` 亮黄** | ⚠️ **不是绿**——纯绿 RGB 在 16 色终端里会变成黄 |
| `(22,198,12)`（`BrightGreen` 锚点值） | `92` 亮绿 | 连接状态徽标（成功态）用这个 |
| `(205,92,92)` Mocha 红 | `91` 亮红 | 错误态（TG 内置 `Error` 方案） |

⇒ **语义色必须挑落在目标锚点邻域的 RGB**：不要把"绿"随手改成 Mocha 绿，否则 16 色终端里会变成"连接状态=黄"。

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
| Terminal.Gui 版本 | **2.4.10.0**，vendored 于 `Modules/Terminal.Gui/2.4.10/`（**已入版本库**，全仓库单副本） |
| 模块导入耗时 | ≈ **207 ms**（冷导入，`-NoProfile`） |
| 导入后是否已加载 TG | **否** —— 惰性加载，模块导入**不**给 Shell 启动增加负担 |
| `Get-TguiContext` 首次 / 二次 | **28.9 ms** / **1.2 ms**（ALC 与 TG 反射句柄有缓存） |
| 仪表盘窗口组装 | 首次 ≈ **840 ms**（TG 静态初始化 + JIT，一次性），稳态 ≈ **30–45 ms** |

### 2.13 SSH 主机仪表盘（2026-10-31 重构，`sss` 无 `-HostName` 路径）

`sss` 的**SSH 主机选择**从"普通单表格"升级为多区域仪表盘。整条链路：

```
Start-TmuxSession → Show-HostSelector(分发器, 对外契约不变)
                  → Show-SshHostDashboard(业务装配: 档案 + 活动历史)
                  → Invoke-SshHostDashboard(事件循环: 键盘 / 异步详情 / 缩放)
```

> **旧轨保留但不再是默认路径**：`Invoke-TguiHostSelector` / `New-TguiHostSelectorWindow` /
> `Get-HostSelectorRow` 仍在模块内、仍可被单独调用（`New-TguiHostSelectorWindow.Tests.ps1` 继续覆盖），
> 只是 `Show-HostSelector` 不再分发到它。这满足"不删除现有可用功能"。

#### 2.13.1 屏幕布局

```text
ShellPrompt · SSH 主机                            上次: deb          ← 行 0 标题带(左=标识 / 右=上次使用)
 All  AWS  DigitalOcean  Local  Other                                ← 行 1 分类导航(当前分类紫底)
┌─ ● deb        ▸prod  #prod #web   2h        ┐                      ← 行 2..H-3
│  ● web        ▸prod  #prod         刚刚       │ ┌ Connection ─────┐ ← 左=主机列表(自定义行)
│  ● local                            3d        │ │ Host    deb     │ ← 中=竖线分隔
│  ● do1        ▸dev   #dev          —         │ │ Address 10.0.0.1│ ← 右=详情卡片
└──────────────────────────────────────────────┘ │ Port    22      │
                                                  │ User    root    │
                                                  │ Status  ● 在线  │
                                                  └─────────────────┘
分类 All · 4/12 台                                                  ← 行 H-2 信息/搜索行
Enter 连接 │ / 搜索 │ Tab 切换区域 │ ↑↓ 选择主机 │ ←→ 切换分类 │ Esc 退出   ← 行 H-1 快捷键栏
```

- **行分配**：标题带 / 分类导航 / 主体区（`Dim.Fill`）/ 信息行 / 快捷键栏（贴底）。
  缩放时整窗重建（几何变了），**分类切换与搜索过滤不重建**。
- **窄屏响应式**：`< 72` 列**收起右侧详情**、列表吃满整宽；`72–99` 列左右各半；
  `>= 100` 列表固定 56 列（再宽只把详情拉宽）。详情卡片矮时按
  `Infrastructure → Tags → Activity` 的次序整卡收起，**Connection 永远保留**。
- **窗口 `BorderStyle` 置空**：置空后内容区等于整个 Frame，绝对行号才与屏幕行号对齐
  （与 tmux 仪表盘同一约定，§2.2）。

#### 2.13.2 组件选型（全部基于 vendored 2.4.10 反射实测）

| 区域 | 组件 | 为什么 |
|---|---|---|
| 分类导航 | **自定义 Label 条** | 2.4.10 **没有 `TabView`**（只有 `Terminal.Gui.Views.Tabs`，纯标签条无内容面板）。当前分类用 `CategoryActive`（白字紫底）着色成"色块"，其余 `Category`（深灰）。分类名**全部由真实档案推导**（§2.13.4）。 |
| 主机列表 | **自定义行列表**（容器 View + 每行 6 个 Label） | `TableView` 每次选中变化都把**整表**标脏（实测 1760 单元格 / 17.9 ms），是 100–200 ms 延迟的根因。自定义行列表只改旧/新两行（实测 348 单元格 / 12.7 ms）。六个 Label 分别承载：背景条 / 状态点 / 名称 / 分组 / 标签 / 最后活跃。 |
| 详情面板 | **4 个 `FrameView`** 竖排 | `FrameView` 有独立 `Title` + 边框方案，内容子视图各取自己的方案 —— 于是"暗灰细边框 + 亮字内容 + 紫色标题"能同卡共存。 |
| 快捷键栏 | **单个 `Label`** | `StatusBar`/`Shortcut` 用 `Key.ToString()` 渲染键名，而 `Key` 只有 A–Z / D0–D9 / 导航键 —— **没有 `/`，也没有 `↑↓` 组合键**（`Key(string)` 对多字符串直接抛 `Invalid key string`）。用 Shortcut 只能把 `↑↓` 退化成一个真实键（如 `Esc`），底栏会显示 `Esc 选择主机`，**与实际键位不一致**。Label 能逐字写出 Goal 要求的清单，还能自己算宽度预算（`StatusBar` 不换行，放不下就在右端硬截断）。 |

#### 2.13.3 键位（唯一事实来源 = `Invoke-SshHostDashboardKey`）

| 键 | 动作 | 说明 |
|----|------|------|
| `↑` / `↓` | 移动选中 | **只重刷旧/新两行**；绝不发网络请求 |
| `Enter` | 连接选中主机 | 返回 `.Value` = 主机名，交回 `Start-TmuxSession` |
| `/` | 进入搜索 | 搜索框获得焦点，打字**实时过滤**（纯本地） |
| `Tab` | 切换区域 | 列表 ↔ 搜索框（底栏文案随焦点切换，避免"写着按不到"） |
| `←` / `→` | 切换分类 | 纯本地过滤，**不发任何 SSH 请求** |
| `Esc` | 退出 / 取消搜索 | 搜索态下先取消搜索回列表；列表态下退出仪表盘 |

- **底栏是纯展示件**：键位语义全部由编排层的 `KeyDown` 处理器实现，底栏只复述事实。
- **底栏按宽度取舍**：`Priority` 决定"被舍掉的顺序"（数字小 = 更晚被舍），`Order` 决定显示顺序。
  `Esc` 的 Priority 特意排第二位 —— 它是本仪表盘**唯一**的退出键，窄屏下必须比
  `/` / `Tab` / `←→` 更晚被舍掉（"用户看不到怎么退出是不可接受的"，与 §2.4 同源规则）。
- **事件路由**（2.4.10 实测，`.agent_cache/dash-probe/p33-keyevent-run.ps1`）：
  `KeyDown` **先到焦点视图、再冒泡到 Window**；在焦点视图里把 `Key.Handled` 置 `$true`
  即阻止冒泡与默认处理。因此列表容器与 Window 各挂一个处理器，**列表里处理过的键
  一律置 `Handled`**，不会双触发。搜索框的 `Enter`/`Tab`/`Esc` 由搜索框自己的处理器接管，
  通用处理器在这些键上返回 `$false`（同样防双触发）。

#### 2.13.4 分类数据来源（不写死示例主机）

分类名由**真实主机档案**推导（`Get-SshHostCategoryList`）：

1. 恒以 `All` 开头；
2. 其后是档案里**实际出现过的 Provider**（首次出现顺序，大小写不敏感去重）；
3. 存在本地主机（`HostName` ∈ `localhost` / `127.0.0.1` / `::1`）时追加 `Local`；
4. 存在"无 Provider 且非本地"的主机时追加 `Other`。

`Provider` / `Region` / `Tags` / `Group` **只能**来自人写在 `Host` 块前的元数据注释
（`# @provider AWS` / `# @region us-east-1` / `# @tags prod,web` / `# @group prod`），
`Include` 进来的文件缺省用**文件名**当分组。没写就留空 —— **绝不用主机名去猜云厂商**。

#### 2.13.5 异步详情加载契约

```text
选中变化(键盘回调, 内存态, 零网络)
  └─ Set-SshHostDetailBasic   本地字段(Host/Address/Port/User/Tags/Group/Provider/Region + 本地活动)立即落位
  └─ 有 DetailByHost 缓存 ? 立即回填 : 显示"● 探测中…"
       │
       └─ AddTimeout 心跳(120ms, 主循环/UI 线程)
            ├─ 选中主机变了 → 旧的在飞请求 **Stop-Job 显式取消**
            ├─ 在飞请求完成 → Receive-SshHostDetailTask(**绝不 Wait**) 收割
            │    ├─ 结果进 DetailByHost / StatusByHost 缓存(真实数据)
            │    ├─ 列表对应行 Sync-SshHostListRow 只刷新那一行
            │    └─ 面板回填 **必须** RequestId 与主机名双重匹配
            ├─ 选中主机还没详情 → Start-SshHostDetailTask(后台线程作业)
            └─ 否则巡检: 当前**可视窗口内**下一台没探测过的主机(填列表状态点)
```

四条硬约束：

1. **键盘热路径零网络**：`KeyDown` 回调里连"提交后台探测"都不做 ——
   `Start-ThreadJob` 自身有 ~50 ms 的 runspace 创建开销（实测提交 24 ms），
   放在按键路径上就是白给的延迟。提交动作交给心跳（与按键处理错开）。
2. **旧请求不覆盖新选择**：每次**主机真的变了**才生成新请求标识（`"<host>#<seq>"`）；
   面板回填前校验 `RequestId` + 主机名双重匹配。同一台主机的在飞探测**不会**因为
   重复选中而被自己判成"旧请求"。
3. **不重复查询**：探测结果按主机名缓存（`DetailByHost`），回到已探测过的主机直接回填缓存。
4. **三态明确**：加载中 `● 探测中…`（暗灰）/ 失败 `✗ <原因>`（亮红）/ 未知 `● 未知`（灰）——
   **绝不为了填满卡片而伪造数据**。`Activity` 卡片没有本地记录时明确写 `无记录` / `—`。

> **为什么用 `Application.AddTimeout`**：2.4.10 的 `AddTimeout(TimeSpan, Func<bool>)`
> 在**主循环**里触发，回调本身就在 UI 线程上 —— "后台作业结果回填 UI"因此不需要任何
> 跨线程调度原语。回调返回 `true` 继续、`false` 停止（实测 p33 已验证）。
> 心跳令牌随 `Shutdown` 失效，下一轮 `Init` 重新注册（与 §2.11 的订阅生命周期同一道理）。

#### 2.13.6 性能根因与修复（Goal 四）

**根因（实测，非预设）**：旧 `sss` 主机选择器用 `TableView`；移动选中时 TG 把
**整张表**标记为脏（`NeedsDrawRect = {0,0,80,22}` = 1760 单元格），每次按键都重绘整表。
键盘回调本身只有 0.12 ms —— **瓶颈是重绘量，不是事件处理，也不是网络**
（旧路径键盘回调里本来就没有 SSH/tmux 命令）。因此修复方向是**缩小脏区**，不是加缓冲。

前后对比（30 台主机、同一进程、`Application.LayoutAndDraw($false)`，样本 60 次/档；
测量脚本是一次性诊断产物 `p38-perf.ps1` / 报告 `p38-stderr.log`，**不随仓库分发**，
复跑方式见 `.agent_cache/dash-probe/`（该目录在 `.gitignore` 内））：

| 指标 | 优化前（TableView） | 优化后（自定义行列表） | 变化 |
|---|---|---|---|
| 键盘回调均值 | 0.12 ms | 2.60 ms | ↑（**实际工作从绘制阶段挪到了回调里**，见下） |
| 重绘 `LayoutAndDraw` 均值 | 17.17 ms | 8.75 ms | **1.96× 更快** |
| **按键 → 界面更新总量（均值）** | **17.30 ms** | **11.35 ms** | **1.52× 更快** |
| 同上（中位数） | 16.79 ms | 10.71 ms | 1.57× 更快 |
| 同上（p95） | 18.12 ms | 13.97 ms | 1.30× 更快 |
| **每按键重绘单元格** | **1760** | **348** | **5.05× 更少** |
| 远程探测提交耗时 | — | 24.6 ms（在心跳里，不在按键路径） | — |
| 20 次连续切换（1.5 s 探测在飞时） | — | **25.0 ms 总计**，不等待探测 | 证明不阻塞 |

> **为什么"回调变慢"反而是好事**：旧路径的 0.12 ms 只是"设了个选中属性"，
> 真正的 17.2 ms 全在随后的整表重绘里；新路径把"改两行 Label + 刷新详情字段"
> 的 2.6 ms 显式花在回调里，换来重绘从 17.2 ms 降到 8.7 ms。**用户感知的总延迟
> 由 17.3 ms 降到 11.3 ms**，而**终端输出量降到 1/5** —— 在真实终端（Windows
> Terminal）上这一项才是 100–200 ms 延迟的主因，因此真机收益大于本表。
>
> 本容器**无 TTY**：`ansi` 驱动不写出任何终端字节（stdout 增量为 0），
> 因此"每次按键写了多少字节"**无法实测**，只能用 TG 自己的脏区单元格数作为代理量。
> 真机上输出量正比于脏区面积。

配套的四处优化（都在按键/刷新路径上，均有实测依据）：

1. `Set-SshHostListScroll` **逐槽比对**：内容与选中态都没变的槽位直接跳过
   （`SetScheme`/`Text` 赋值都会把 Label 标脏），滚动一行的脏区从"整屏"缩回"进出的两行"。
2. `Set-SshHostDetailLabelText` / `Set-SshHostDetailLabelScheme` **等值跳过**：
   TG 2.4.10 的 `View.SetScheme` **不是幂等 no-op**（会无条件标脏）。
3. `Set-DetailValue` 用**原值登记表**：原值没变就连截断计算都不做
   （详情面板 12 个字段，切换主机时大部分原值相同）。
4. `Get-TguiTextWidth` 加 **ASCII 快路径**：`0x20..0x7E` 恒为 1 列，用长度直接给答案，
   跳过解释执行的逐字符循环。

> **仍可再压的一处（已知、未做）**：`Get-SshHostDashboardRow` 整表重算约 **16 ms/30 台**，
> 主要是 `PSCustomObject` 30 属性 × 30 行的构造开销（排序本身只占 0.13 ms）。
> 它**只发生在分类切换与搜索输入**，不在 ↑↓ 热路径上，因此本轮没动；
> 若后续要再压，把行模型换成 PowerShell `class` 即可（代价是测试与序列化面变大）。

#### 2.13.7 无头渲染取证（已验证）

> **本节只验视图层**。编排层（真事件循环）的端到端取证见 [§2.13.8](#2138-编排层端到端取证已验证)。

Terminal.Gui 2.4.10 未暴露 `FakeDriver`，但**渲染结果先落在 `driver.Contents`
(`Cell[,]`)** 再写给终端 —— 因此 `Init + Begin + LayoutAndDraw` 之后，
缓冲区里就是"本该画到屏幕上的那一屏"，可以**逐格**导出文本与属性取证。

已验证的六档（`Application.Screen` 显式设为目标尺寸；`Cell` 的字符内容是
**`Grapheme`** 属性，不是 `Rune`；全角字符占两格，缓冲区里第二个格是续格）：

| 档位 | 验证结论 |
|---|---|
| 120×35 | 标题带 + 右对齐"上次: deb"、分类条、12 行主机列表、竖线分隔、四张详情卡、信息行、底栏 **全部就位**；选中行底色 = **Magenta（#FF00FF）**、状态点前景 = Gray（选中态变体）；未选中行底色 = Black |
| 160×45 | 同上，详情卡随宽度拉伸，无溢出 |
| 72×20 | 详情面板保留；无活动记录的主机显示 `无记录` / `—` / `—`（**不伪造**）；底栏舍弃 `←→ 切换分类`、**保留 `Esc 退出`**；长主机名与标签以 `…` 截断且**列对齐不乱** |
| 40×12 | 详情面板收起、列表吃满整宽；底栏只剩 `Enter 连接 │ ↑↓ 选择主机 │ Esc 退出`（`Esc` 仍可见） |
| 搜索态（`/do`） | 只剩 `do-dev` / `do-staging`；信息行被搜索框取代；底栏切到搜索变体 `Enter 应用 │ Tab 返回列表 │ Esc 取消` |
| CJK | `裸机-测试` 等全角主机名按**显示宽度**占两格，与其它行的标签列、时间列**仍然对齐**；`▁▅ █▃▁` 直方图正常 |

> 取证脚本是一次性诊断产物（`.agent_cache/dash-probe/p40-render.ps1`），**不随仓库分发**。
> 上述结论中"未选中行底色 = Black、选中行 = Magenta"是**逐格读 `Cell.Attribute`**
> 得到的硬证据，不是目测。

#### 2.13.8 编排层端到端取证（已验证）

§2.13.7 验的是**视图层**。为了证明"真正跑起来的那条链
（`Show-HostSelector` → `Show-SshHostDashboard` → `Invoke-SshHostDashboard`）
产出的是新仪表盘而不是旧单表格"，另做了一轮**编排层**取证：让
`Invoke-SshHostDashboard` 走完它自己的 `Init → AddTimeout → Run → Shutdown`，
在**事件循环运行中**抓帧并注入按键。

手法（可复现，不需要真终端）：给两个模块作用域内的函数打**影子** ——
`Test-TmuxTuiInteractive` 恒 `$true`（容器无 TTY，否则护栏直接返回），
以及 `Update-SshHostDashboardProbe`（编排层每 120ms 在**主循环**里被调用的
心跳回调）改为"先调原实现、再抓一帧 `driver.Contents`、再注入下一个按键"。
于是"抓帧 + 注键"都发生在 **UI 线程的主循环**上，不需要任何跨线程原语。

抓到的三帧（合成 6 台主机：AWS×2 / DigitalOcean / 本机 / 无 Provider / 中文名）：

| 帧 | 触发 | 观测 |
|---|---|---|
| frame1 | 首屏 | 标题带 + 分类条(`All AWS DigitalOcean Local Other`) + 主机列表 + 分隔线 + Connection/Activity/Tags 卡片；详情 `Host=deb / Address=10.0.0.11 / Port=22 / User=root`；连接状态 **`● 探测中`**（远端未到，**不提前显示在线**） |
| frame2 | `↓` | 选中切到 `do-dev`，详情面板**同步**换成 `do-dev / 10.0.0.2 / dev`，列表与详情保持一致 |
| frame3 | `→` | 分类切到 `AWS`，列表**只剩** `deb` + `db-prod`（`do-dev`/`local-box`/`bare-host`/中文主机被过滤掉），详情回到 `deb` |

⇒ 键位、分类过滤、异步态、详情联动在**真实事件循环**里均按契约工作。

> 取证脚本是一次性诊断产物（`.agent_cache/dash-probe/p41-orchestrator.ps1`），**不随仓库分发**。

#### 2.13.9 已知限制

- **状态点只对"探测过的"主机着色**：选中主机会立即探测，可视窗口内的其余主机由心跳
  逐台巡检。没探测过的显示灰色 `● 未知` —— 这是**如实**呈现，不是缺陷。
  主机很多时巡检会持续占用网络（每台一次 SSH 往返，`TimeoutSec` 默认 6 s）；
  离开可视窗口的主机不再巡检。
- **EC2 等云主机详情未实现**：仓库没有云 API 集成，`Infrastructure` 卡片只展示
  从 ssh config 元数据注释读到的 `Provider` / `Region`，**没有数据就不显示该卡片**。
- **本容器无法验证真机显示效果**：Terminal.Gui 2.4.10 未暴露 `FakeDriver`，
  `script` 也无法创建伪终端（沙箱 `Permission denied`），因此**真机抓屏证据缺失**。
  无头证据止于**逐格渲染取证**（§2.13.7）、布局几何、方案配色值、脏区/耗时测量
  与按键路由行为探针。真机验收清单见第五章。

---

## 三、vendored 依赖归属

Terminal.Gui 采用**独立版本目录 + 单一副本**：`Modules/Terminal.Gui/<ver>/`。演进过程与备选方案见 git 历史，此处只记录现行结论与维护方式。

### 3.1 现状（事实）

| 事实 | 值 |
|------|---|
| Terminal.Gui 版本 | **2.4.10.0**（`AssemblyVersion` = `AssemblyFileVersion`），目标框架 `.NETCoreApp,v10.0` |
| vendored 位置 | `Modules/Terminal.Gui/2.4.10/` —— **单一副本**，独立版本目录入版本库 |
| 同目录托管依赖 | `ColorHelper` / `JetBrains.Annotations` / `Markdig` / `Microsoft.Extensions.DependencyInjection.Abstractions` / `Microsoft.Extensions.Logging.Abstractions` / `Onigwrap` / `System.IO.Abstractions` 系列 / `Testably.Abstractions.FileSystem.Interface` / `TextMateSharp(.Grammars)` / `Wcwidth`（共 13 个依赖 DLL，与 TG 同目录） |
| 消费方 | `sss` 仪表盘与 SSH 主机选择器 —— **独立不可回收 ALC**（`ShellPrompt-Tgui`），依赖按“同目录同名文件”回载 |
| 同进程内的 TG 类型身份 | **一套**（`ShellPrompt-Tgui` ALC） |

### 3.2 结论与理由

1. **TG 是全仓唯一的交互式 UI 依赖**，独立版本目录 + 独立 ALC 的组合满足“单副本、版本钉死、类型身份一致”。
2. ALC 从独立目录按同目录规则解析依赖；“主机选择器能否弹出”由 [`Get-ConsoleUiBackend`](../../ShellPrompt/Private/Get-ConsoleUiBackend.ps1) 的 vendored 目录探测显式兜底。
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

## 五、已知限制与验证状态

### 维护记录

历史缺陷的修复过程与根因取证不在此逐条记录（需要时查 git 历史）。现行必须遵守的规则已写在契约小节中：快捷键渲染序见 §2.4，尺寸来源与缩放见 §2.6，配色与 16 色量化见 §2.9，非泛型 `Run` 见 §2.10，Init 周期与事件订阅见 §2.11。

### 真机验收记录（2026-10-30，Windows Terminal + pwsh 7.6.3，arbaleast@G7）

- **已通过**（本轮逐项回填）：#0 内容可见；#5 附着/ detach 交接；#6 新建（n：真实创建后 detach 回仪表盘并刷新，Esc 取消回退）与删除（x：二次确认 `[y/n]` 默认 n）；#2 键位单次触发；#4 缩放（窄窗 STATUS 列按设计隐藏、底栏单渲染、无残影）；#7 SSH 直连（exit 后回仪表盘）；#8 终端还原（备用屏退出后 Shell 历史完整、无双底栏、无 1049 残留）；#9 无 TTY 护栏。
- **遗留风险（不阻断收口）**：
  1. 空态/错误态的"独立空态行"回填证据以文字确认为准（回填截图实际含 1 个会话），未逐字节取证；
  2. 极窄宽度（40–71 列）与 40×10 下限场景未逐档真机复验（无头布局核验零重叠零越界）；
  3. conhost 宿主未验证（本轮仅 Windows Terminal）。
- **2026-10-31 补充**：上列遗留风险 2 已由 **Linux 容器 PTY 取证**覆盖（40×10 / 60×15 / 72×20 / 100×30 / 120×35 / 160×45 六档 + `sessions`/`empty`/`error`/`cjk`/`longname`/`many` 六场景，逐格取色确认无截断、无遮挡、表头/选中行/状态徽标配色可分）。遗留风险 1、3 仍在（Windows Terminal / conhost 宿主未复验）。
- 仪表盘当前**只有一条轨**（见 §一）；若真机再出问题，历史实现走 git 历史回查，不留在工作树。

- **终端宽度下限 40 列**：仪表盘按 **40×10** 起步（`New-TmuxTuiDashboardWindow` 的 `ValidateRange` 与编排层的屏幕夹取一致）。真实终端窄于 40 列时，仪表盘会按 40 列布局 ⇒ **该极端场景存在横向溢出**。宽度 ≥ 72 列起显示 WINDOWS 列、≥ 96 列起显示 STATUS 列（见 §2.2 / §2.6）。
- **首次拉起的一次性延迟**：首次进入 `sss` 时 Terminal.Gui 静态初始化 + JIT 约 **0.84 s**（之后稳态 30–45 ms）；模块导入阶段**不**加载 Terminal.Gui（惰性），因此不影响 Shell 启动耗时。详见 §2.12。
- **绘制级断言无法无头执行**：Terminal.Gui 2.4.10 未暴露 `FakeDriver` / 公开的 `View.Render`，无头证据止于方案配色值、布局几何、IL 反汇编与子视图/`IsRunning` 行为探针；"内容确实可见"由真机清单第 0 项确认（已通过）。

### 真机验收清单（Windows Terminal + pwsh 7.6+，逐项打勾）

准备：对一台真实 tmux 主机运行 `sss`（无渲染开关，仪表盘只有一条轨）。

| # | 验收点 | 通过标准 |
|---|--------|----------|
| 0 | **内容可见** | 标题行、统计行、会话表单元格、快捷键栏的**文字全部可见**（不是"只有边框"）；前景与背景不同色 |
| 1 | 布局观感 | 标题带（产品标识 / 主机 / 右对齐连接状态）、统计行、会话表格、底部快捷键栏各占一行；100×30 / 120×35 / 160×45 三档均无遮挡叠行 |
| 2 | 键位 | ↑↓ 移动选中、Enter 附着、N 新建、R 刷新、S 直连、X 删除（二次确认）、Esc/Q 退出，各键一次触发（无重复分发） |
| 3 | 空态/错误态 | 无会话时**表格隐藏**、主体区居中给可执行指引（不伪造表格行）；断网时错误码 + 指引在状态标题行，表格区不出现错误文本 |
| 4 | 缩放 | 运行中拖拽窗口尺寸：整窗重建无残影；窄窗口 STATUS/WINDOWS 列自动隐藏 |
| 5 | 附着交接 | Enter 附着 → 仪表盘消失 → 真实 tmux 全屏；detach（`d`）→ 仪表盘重新出现且会话列表已刷新，选中行尽量保持 |
| 6 | 新建/删除交接 | N 新建（或 Esc 取消：**不发生屏幕翻转**）回到仪表盘；X 删除含二次确认（默认 n），完成后回仪表盘刷新 |
| 7 | SSH 直连交接 | S 直连 → 全屏 ssh；exit 后回仪表盘 |
| 8 | 终端还原 | Q/Esc、**Ctrl+C**、Ctrl+C + 异常路径退出后：光标/输入模式正常、Shell 历史完整、无双底栏、无 1049 残留（备用屏单层：TG 独占，模块不发 1049） |
| 9 | 无 TTY 护栏 | `pwsh -c "Start-TmuxSession deb"`（非交互重定向）不挂死，直接返回并给出跳过警告 |

登记结果时注明日期与窗口宿主（Windows Terminal / conhost）。

### SSH 主机仪表盘真机验收清单（维护者，交互行为待真机验证）

> 主机仪表盘与 tmux 仪表盘共享同一套 Terminal.Gui v2 终端生命周期（组装层 + 事件循环）。
> 无头门禁已覆盖：整窗组装与布局几何（40/60/72/100/120/160 六档无溢出）、分类推导与切换、
> 行模型排序/过滤/相对时间、列表局部刷新（只脏两行）、详情面板三态落位、
> 旧请求不覆盖新选择、键位语义、非交互护栏。以下交互行为依赖真实 TTY，
> **不得凭无头探针宣称通过**。

准备：`Clear-Host` 后对一台含 3+ 主机、且 ssh config 里写了
`# @provider` / `# @tags` / `# @group` 元数据注释的配置运行 `sss`，
窗口宿主 = Windows Terminal + pwsh 7.6+。

| # | 验收点 | 通过标准 |
|---|--------|----------|
| 0 | **内容可见** | 标题带（左标识 + 右"上次: …"）、分类导航条、左主机列表、右详情四卡、信息行、底部快捷键栏全部可见；前景背景不同色（不是只有边框） |
| 1 | **视觉层次** | 选中行**整行紫底**；状态点绿/红/灰可分；标签为主色紫、分组与时间为暗灰；主机名视觉权重最高 |
| 2 | **分类导航** | 分类来自真实配置（写 `# @provider AWS` 才有 AWS 分类，未写的主机落 `Other`）；`←→` 切换分类后列表即时过滤且**不出现网络请求**（可用 `ss` 观察）；当前分类紫底高亮 |
| 3 | **键位** | `↑↓` 移动选中（**无 100–200 ms 延迟**，连续快按跟手）；`Enter` 连接并进入 tmux 仪表盘；`/` 进搜索；`Tab` 在列表↔搜索框切换；`Esc` 退出 |
| 4 | **搜索过滤** | `/` 后打字**实时**过滤（不卡顿）；`Enter` 应用并回列表；`Esc` 取消并清空过滤；无匹配行时 Enter 不退出也不崩溃 |
| 5 | **异步详情** | 选中主机后**基础信息立即变化**（Host/Address/Port/User/Tags/Group），状态行先显示 `● 探测中…` 再变成 `● 在线`/`✗ 错误码`；探测期间 `↑↓` **依然跟手** |
| 6 | **旧请求隔离** | 快速连续切换多台主机后停在最后一台，详情卡片**必须是最后一台**的信息（不允许被中途某台的迟到结果覆盖） |
| 7 | **无数据不伪造** | 没写过活动记录的主机，Activity 卡片显示 `无记录` / `—`；没有 Provider 的主机**不显示** Infrastructure 卡片，也不出现假数据 |
| 8 | **缩放** | 运行中拖拽窗口：< 72 列收起右详情、列表吃满；72–160 列布局无重叠无越界；底栏按宽度取舍（但 `Esc 退出` 必须始终可见） |
| 9 | **中文/Unicode** | 中文主机名、中文标签截断后列对齐正确（`…` 收尾，不出现半个全角字）；`●` / `│` / `—` / `▁▃▅█` 渲染正常无错位 |
| 10 | **终端还原** | `Esc` 退出后：备用屏退层（无 1049 残留）、光标正常、Shell 历史完整 |
| 11 | **返回值契约** | `Esc` → 下游不建会话不连 SSH；`Enter` → `.Value` 透传主机名，连接参数与重构前一致 |
| 12 | **LastHost 回归** | 上次连接的主机在列表置顶且标题带右侧显示"上次: &lt;host&gt;"；连接成功后下次进入仍置顶 |

登记结果时注明日期 + 窗口宿主 + 宿主 OS。

---

## 相关文档

- [架构](architecture.md) —— 模块目录树与加载流程
- [命令一览](commands.md) —— 公开命令与交互流程
- [配置](configuration.md) —— 配置域与优先级
- [`docs/agents/architecture.md`](../agents/architecture.md) —— 架构不变量与 tmux 管理器交互契约
