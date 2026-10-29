# 🎛️ 交互菜单后端（PSTui GridView 单轨）

`sss`（[`Start-TmuxSession`](../../ShellPrompt/Public/Start-TmuxSession.ps1)）里的**三个交互菜单（主机选择 / 会话管理 / 会话列表）**是**单轨**的：唯一渲染实现是 [`Modules/PSTui`](../../Modules/PSTui/1.0.5/README.md) 的 `Out-ConsoleGridView` 表格视图（[`Invoke-GridViewMenu.ps1`](../../ShellPrompt/Private/Invoke-GridViewMenu.ps1)）。自研 ANSI 降级轨（`AnsiFallback`）已于 2026-10-18 整体移除。

主轨可用性检测由 [`Get-ConsoleUiBackend`](../../ShellPrompt/Private/Get-ConsoleUiBackend.ps1) 提供（`PSTui` 可发现性 / 同名命令冲突 / `Terminal.Gui` 主版本争用 / 交互式宿主），其中 `Backend` **恒为** `'GridView'`。

**检测是惰性的（2026-10-18 起）**：模块加载期**不再**执行检测（实测该项是模块导入阶段的最大单一热点，约 500ms，且启动期根本用不到），改为首次真正需要时（`Get-ConsoleUiState` / `Assert-ConsoleUiReady`）现场检测一次，结果缓存到 `$script:ConsoleUiBackend`，后续复用。

| 调用 | 时机 | 耗时 |
|------|------|------|
| 模块加载 | 不检测，`$script:ConsoleUiBackend` 保持 `$null` | 0ms |
| 首次 `Get-ConsoleUiState` | 现场检测并缓存 | 约 360–500ms（一次性；旧口径在模块加载期实测约 500ms） |
| 后续调用 | 复用缓存 | 约 0–1ms |

| 检测项 | 判定 |
|------|------|
| PowerShell ≥ 7.6 | `ShellPrompt.psd1` 已在导入阶段把守；检测函数内再校验一次 |
| `PSTui` 可发现 | 模块必须已安装（仓库内置 `Modules/PSTui/`） |
| 无同名命令冲突 | 环境中不得存在其它 `Out-ConsoleGridView` 来源 |
| `Terminal.Gui` 主版本为 2 | 避免与其它 Terminal.Gui 主版本争用 |
| 交互式宿主 | stdin 未被重定向（管道 / CI / 输入重定向场景不满足） |

**Starship 同步 init（2026-10-18 起回退到 P3 优化前）**：profile 阶段 2 `Invoke-DeferredInit` 同步执行 `starship init powershell --print-full-init`，starship 自身替换 `Function:prompt` 完成接管; `Initialize-StarshipLazy` 与 `Register-WttrPromptWrapper` 全链路已随方案 B 部分回退一并移除（该撤销未记入 CHANGELOG，以源码与 [`docs/agents/architecture.md`](../agents/architecture.md) 为准）。

**fnm env 走缓存路径（2026-10-18 起）**：`fnm env --use-on-cd --shell powershell` 子进程 (实测 ~88~124ms) 改为走 `Initialize-FnmEnvironment` 缓存路径. 缓存键 = `fnm|<exe mtime ticks>|<exe length>|powershell|ns=<node version list>` (fnm 可执行文件变化 / `fnm install` / `fnm uninstall` 自动失效), 缓存文件 `$env:LOCALAPPDATA\ShellPrompt\fnm-env.json`. **PATH 永不缓存**(避免静默覆盖用户临时 PATH 修改); 运行时基于**当前** `$env:PATH` 重算 fnm 注入路径. 失败保底走 `Set-FnmEnvironmentByFallback` 直接跑 `fnm env` 子进程 —— 正确性优先于速度.

**主轨不可用时不再静默降级**：分发器在调用实现前统一执行 `Assert-ConsoleUiReady -Feature <功能名>`，抛出**可定位的终止错误**（含功能名与具体原因），例如：

```
[ShellPrompt] tmux 会话列表菜单 需要控制台 UI 主轨 (PSTui GridView), 但当前环境不可用: ...
```

模块**加载本身**不会因此失败（检测异常时 `Get-ConsoleUiState` 兜底返回 `Available=$false` 的可诊断对象，只 `Write-Verbose` 记录，**不向 stderr 写入任何噪声**），只有真正调用交互菜单时才抛错。

## 对外契约

[`Show-HostSelector`](../../ShellPrompt/Private/Show-HostSelector.ps1) / [`Show-SessionManager`](../../ShellPrompt/Private/Show-SessionManager.ps1) / [`Show-TmuxSessionList`](../../ShellPrompt/Private/Show-TmuxSessionList.ps1) 是纯分发器，返回 `PSCustomObject`（`.Value` 为选中值，`$null` 表示用户取消）。调用方无需感知渲染实现细节。

## 会话管理菜单文案（Action ↔ Value）

会话管理菜单只有 **Action**（可见文案）与 **State**（状态徽章）两列，外加隐藏列 `Disabled` / `Value`。

> **说明列（Desc）已于 2026-10-19 删除**（与 Action 重复，释放约 16 字宽度）。文档中不再出现 Desc 列。

| Action（可见文案） | Value（隐藏列，选中返回值） | State 徽章 |
|--------|-------|------|
| `附着/恢复 tmux 会话` | `Attach` | `● 已附着 N`（N>0 时） |
| `删除 tmux 会话` | `Remove` | `⚠ 危险` |
| `创建新 tmux 会话` | `New` | — |
| `直接 SSH 登录` | `Ssh` | `⚠ 备选` |
| `刷新会话列表` | `Refresh` | — |

> 仅有会话时才出现「附着/恢复」「删除」两行；无会话时菜单只含「创建」「SSH 登录」「刷新」。菜单实现见 [`Invoke-GridViewMenu.ps1`](../../ShellPrompt/Private/Invoke-GridViewMenu.ps1)，行构造见 [`Get-GridViewManagerRow.ps1`](../../ShellPrompt/Private/Get-GridViewManagerRow.ps1)。修改文案时在 `Get-GridViewManagerRow.ps1` 内调整。

## 会话列表的「已附着 / 已分离」状态

`sss` 的会话列表会为每个 tmux 会话显示一个 **State** 状态列，用于区分该会话当前是否被终端附着：

| 状态 | 徽章 | 含义 |
|------|------|------|
| 已附着 | `● 已附着` | 该 tmux 会话已被某个客户端附着，屏幕内容正在被实时共享；对它执行 `attach` 会提示 `sessions should be nested with care` |
| 已分离 | `○ 已分离` | 该会话当前无客户端附着，可安全 `attach` 进入 |

标题栏的 **「附 N / 分 M」** 与之配套：`N` = 已附着会话数，`M` = 已分离会话数。两个数字直接来自状态列的判定结果，与下方表格逐行一致。

状态数据的来源与优先级（见 [`Get-TmuxSessions.ps1`](../../ShellPrompt/Private/Get-TmuxSessions.ps1)）：

1. **机器可读路径（首选）**：`tmux list-sessions -F "TMUX_SESSION #{session_attached} #{session_windows} #{session_name}"`，直接取 tmux 的权威字段 `session_attached`。**会话名放在格式串最后**，因此会话名中含空格、冒号（如 `my session`、`a:b`）都不会被误切分。
2. **`tmux ls` 容错回退**：机器可读路径不可用（老版本 tmux / 环境异常）时，回退到宽松正则解析 `tmux ls` 文本输出，能识别 `[attached]` 方括号形态、`window`/`windows` 单复数、缺 `(created …)` 的精简形态以及尾部附加字段。
3. **异常降级**：tmux 未安装、无 server 运行、输出为空或不可解析时，返回**空集合**并给出告警，**不会抛异常**；此时**不会弹出菜单**——会话列表入口会 `Write-Warning "没有可用的 tmux 会话"` 并返回 `$null`。

> State 列与「附 N / 分 M」在会话列表打开的**那一刻**求值。tmux 侧的附着状态随时可能变化（例如你在另一个标签页 attach 了某个会话），所以表格是**打开时快照**，不会自行变化。

## 「刷新会话列表」的使用时机

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

## 查看主轨检测结果（调试用）

```powershell
# 查看当前主轨可用性检测结果（Backend 恒为 'GridView'）
# 注意: 惰性检测, 首次调用会现场跑一次检测并缓存结果
& (Get-Module ShellPrompt) { Get-ConsoleUiState | Format-List }
```

> 交互菜单不再提供 `-Backend` 参数，也不存在 `UI.Backend` 配置项。旧配置文件中的 `UI.Backend = 'AnsiFallback'` 将**被忽略**（不报错），主轨不可用时直接抛终止错误。

## 配置项（`$HOME/.ShellPrompt/config.ps1`）

| 键 | 默认 | 说明 |
|----|------|------|
| `UI.GridViewFocus` | `Table` | `Table` = 焦点在表格; `Filter` = 焦点在筛选框（对应旧 ANSI 菜单的 `Q1=A` 实时过滤手感） |
| `UI.GridViewFullScreen` | `$true` | `Out-ConsoleGridView` 是否全屏渲染（alternate screen buffer；标题/提示在弹窗后不可见，退出后恢复） |

## GridView 配色（Terminal.Gui `Scheme` 槽位）

主轨表格的配色由 [`Initialize-Config.ps1`](../../ShellPrompt/Private/Initialize-Config.ps1) 的 `UI.Theme` 域下发，落地逻辑在 [`Set-TgColorScheme.ps1`](../../ShellPrompt/Private/Set-TgColorScheme.ps1)：**就地改写** `SchemeManager` 里**已存在**的 `Base` / `Menu` 两个方案实例（不新增方案名、不写 `ThemeManager.Theme`——在 TG 2.4.10 上该组合会让内部字典与 `Theme` 失配）。

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

## 能力说明（GridView 主轨的限制与补偿）

| 能力项 | GridView 主轨现状 | 补偿手段 |
|---|---|---|
| 行级红色 / 危险项高亮 | PSTui 未开放 Color/Theme API | `State` 列文本（`⚠ 危险` / `⚠ 备选` / `★ 最近`） |
| 底部帮助文本行 | 表格视图无底部帮助区 | 按键说明由 **PSTui 自带状态栏**（`Rows: n \| Enter Accept \| Esc Close`）提供；提示行草案 A.2 已于 2026-10-19 撤回——alternate screen 下菜单上方的提示用户看不到；仓库内 `Write-GridViewHint` 函数随之于 2026-10-29 一并删除 |
| 实时增量过滤 | 无键盘级过滤回调 | `-Focus Filter` 表格筛选框（`UI.GridViewFocus = 'Filter'`） |
| `Disabled` 行灰显 | 不支持渲染禁用态 | `State` 列标注 + 选中后**阻断**并提示 |
| 独立「退出」行 | 表格不再放 Exit 行 | `Esc` / `Ctrl-C` 退出，返回 `$null` |

## 性能特征（GridView 主轨）

| 维度 | `GridView` 主轨 |
|---|---|
| 渲染方式 | PSTui `Out-ConsoleGridView` 表格视图, 宿主内一次性重绘 |
| 每次按键重绘量 | 整表重绘, 由 TG 内部批处理 |
| 整屏清屏 | 无此机制 |
| 非交互终端 / stdin 重定向 | 分层处理：调用交互菜单前 `Assert-ConsoleUiReady` 检测到非交互宿主 → 抛**可定位终止错误**；若重定向绕过检测、`Out-ConsoleGridView` 运行时抛错 → 分发器**兜住异常**，`Write-Warning` 后返回 `$null`（不向调用方抛出） |
| 单个菜单项渲染耗时 | 不适用 (表格单元格) |

**结论**: 「ui 卡顿」问题已消解 —— 三个交互菜单**全部且仅**走 `GridView` 主轨, 逐行绝对定位覆盖的自研 ANSI 渲染实现已随降级轨一并移除, 相关的手写清屏、颜色表补全与三区布局代码均不再存在。

> 真实交互终端的手感无法在自动化环境量化 (stdin 被重定向), 需人工验收：打开/移动/确认/取消各 1 轮、删除确认默认 `n`、空数据警告不弹窗。

## 删除会话的二次确认

`Remove-TmuxSession` 在选中会话后、`tmux kill-session` 之前插入 [`Read-SpectreConfirm`](../../Modules/PwshSpectreConsole/2.6.3/PwshSpectreConsole.psm1) 阻断式确认（默认答案 `n`）。确认不可用（非交互终端）时**按「不删除」处理**，绝不默认放行。
