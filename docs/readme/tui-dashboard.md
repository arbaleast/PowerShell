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
- 驱动名固定为 **`'ansi'`**：`DriverRegistry` 只注册 `'windows'` / `'dotnet'` / `'ansi'` 三个驱动，而 `'dotnet'` 驱动的输入层**无视 `AppModel` 无条件发备用屏序列**，`'ansi'` 驱动才让 `AppModel` 生效——固定 `'ansi'` 才能保证"TG 独占终端"在 Windows Terminal 与 Linux 上行为一致。
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

### 视觉层次与交互修复台账（2026-10-31，全部含 PTY 取证）

取证方式：Linux 容器内用 `script(1)` 建 PTY 抓取**真实渲染流**（`ansi2scr.pl` 还原屏幕快照、`sgrmap.pl` 逐格还原前景/背景色），覆盖 40×10 / 60×15 / 72×20 / 100×30 / 120×35 / 160×45 六档与 `sessions` / `empty` / `error` / `cjk` / `longname` / `many` 六个场景。

| # | 现象（取证） | 根因 | 修复 |
|---|--------------|------|------|
| 1 | **120 列终端上只显示 `#` 与 `SESSION` 两列**，`STATUS` / `WINDOWS` 根本不渲染 | TG 的 `'ansi'` 驱动在 `Init` 后、事件循环跑起来之前 `Application.Screen` 报 **0×0**（它要等终端异步回应 `CSI 18t`），编排层因此按 40×10 兜底 → 列计划按 40 列算 → 两个次要列被当成"窄屏"隐藏 | 尺寸解析收敛到 `Get-TguiTerminalSize`（事件报数 > **终端自身尺寸** > TG Screen > 缺省），见 §2.6 |
| 2 | **表头与选中行渲染完全同色**（都是白字 + 亮黑底），选中行分不清表头 | TG 的 `Focus` 槽位被"聚焦态列头"和"有焦点时的选中行"**共用** | 表头改走 `Menu.Focus`（冰青字 + `Surface1` 底），选中行走 `Base.Focus`（亮白字），前景色不同 |
| 3 | 标题 / 统计 / 正文 / 底栏**四者同色**，页面没有层次 | 全部视图同绑 `Base` | 标题带绑 `Menu`、状态徽标绑 `Dialog`/`Error`、表头绑 `Menu.Focus`、底栏键名走 `Base.HotNormal`（见 §2.9） |
| 4 | **底栏在窄终端被右端硬截断**：40 列只剩 `Enter 附着 │ n 新建 │ r 刷新 │ s SS`，`X`/`Q`/`Esc` 完全不可见 | TG 的 `StatusBar` 不换行；旧实现按"项数"而非"可用列宽"取舍 | 底栏改为**按列宽预算取舍**（每项 `键名宽+标签宽+5`，含末项分隔段），优先级 `Enter > n > q > r > s > x > Esc`——**"退出"排在"刷新"之前**，见 §2.4 |
| 5 | 40 列下标题行被截断，**连接状态看不见** | 标题 / 主机 / 状态挤在同一个 Label 里 | 标题带拆成**左右两片不重叠**的 Label，状态徽标右对齐且宽度由状态文案反推 |
| 6 | 空态 / 错误态仍画出一个**空表格框**（表头 + 边框 + 0 行），像渲染坏了 | 空态与错误态沿用同一张表 | 表格 `Visible = $false`，主体区改为**居中**的可执行指引 |
| 7 | 连接状态是**亮黄色**（不是绿） | TG 的 `'ansi'` 驱动只发 **16 色** ANSI 码，主题 RGB 被量化到最近锚点：Mocha 绿 `(166,227,161)` → **亮黄 `93`** | 亮绿锚点 RGB `(22,198,12)` → `92`（见 §2.9 的量化表） |
| 8 | 空态提示写"刷新"，底栏写"SSH"，两处说法不一致 | 两处各自拼文案 | 两处都从 `Get-TmuxActionDefinition` 取，空态/错误态按上下文拼装 |
| 9 | 会话名列宽是封顶值（40/60/80），其余空间留在框里；末列还会被 TG 拉伸成巨型空列 | 封顶宽度模型 + `ExpandLastColumn` 默认 `$true` | 列宽改为**吃满余量**（`Σ列宽 + 可见列数 + 1 = 终端宽`）并关闭 `ExpandLastColumn` |
| 10 | 终端宽于 128 列时表格只有 128 宽、右侧空一大块 | TG 2.4.10 的 `TableView.MaxCellWidth` 默认 **100**，任何列的单元格宽度被硬顶在 100 列 | 列宽计划侧按 100 封顶（计划 = 渲染）；⚠️ 调大 `MaxCellWidth` 会让 TG 布局**死循环**（实测 102/132 均复现），只能计划侧封顶 |

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
