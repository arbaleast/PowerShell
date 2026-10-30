# 🎛️ 交互菜单后端（PSTui GridView 单轨）

`sss`（[`Start-TmuxSession`](../../ShellPrompt/Public/Start-TmuxSession.ps1)）里的交互界面是**单轨**的：唯一渲染实现是 [`Modules/PSTui`](../../Modules/PSTui/1.0.5/README.md) 的 `Out-ConsoleGridView` 表格视图（[`Invoke-GridViewMenu.ps1`](../../ShellPrompt/Private/Invoke-GridViewMenu.ps1)）。自研 ANSI 降级轨（`AnsiFallback`）已于 2026-10-18 整体移除。**2026-10-30 TUI 重构后**，tmux 管理器只保留**一个表格面板**——会话主视图（正常态列会话，探测失败/无会话时列带错误码的占位面板），全局动作收敛为底部**单行动作条**（单字母键直达）；主机选择菜单与会话列表（删除流程用）维持不变。详见 [tmux 管理器 TUI 仪表盘](tui-dashboard.md)。

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

[`Show-HostSelector`](../../ShellPrompt/Private/Show-HostSelector.ps1) 是纯分发器，返回 `PSCustomObject`（`.Value` 为选中值，`$null` 表示用户取消）。调用方无需感知渲染实现细节。

> **tmux 管理器只有 Terminal.Gui v2 仪表盘一轨**（[tui-dashboard.md](tui-dashboard.md) §二）；GridView 主轨现在只承载 SSH 主机选择器。

## 交互流程（2026-10-30 TUI 重构起）

`sss` 进入主机后，tmux 管理器的界面结构为**单一 Terminal.Gui v2 仪表盘**（状态区 + 会话表 + 快捷键栏）。

> tmux 管理器界面是**单一 Terminal.Gui v2 仪表盘**（状态区 + 会话表 + 快捷键栏），结构与键位契约见 [tui-dashboard.md](tui-dashboard.md)。

键位契约（n 新建 / r 刷新 / s SSH / x 删除 / q 退出 / Esc 退出）的唯一事实来源仍是 [`Get-TmuxActionDefinition.ps1`](../../ShellPrompt/Private/Get-TmuxActionDefinition.ps1)，完整键位表与错误码表见 [tmux 管理器 TUI 仪表盘](tui-dashboard.md)。

### 静默与降级

- **成功路径不再输出任何 toast**（原 `[OK] 正在重新获取会话列表 ...` 已删除）；只有失败才提示。
- **「确实没有会话」与「探测失败」严格区分**：前者在 TGI 仪表盘渲染独立空态行（不伪造表格行，附着/删除标注"不可用"），后者渲染错误码 + 降级指引。失败**绝不会**折叠成空列表。

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

因为列表是打开时的快照，若状态与实际不符（例如刚在别的终端 attach 过），可手动触发一次刷新。

| 刷新入口 | 表现 |
|---------|------|
| 底部动作条的 `r` 键（2026-10-30 起的 tmux 管理器主流程） | 重拉会话并**重新弹出主视图**（每次弹出都取最新快照）；失败态下 `r` 的文案变为「重试」 |
| 删除流程列表最后一行的 `⟳ 刷新会话列表` | 删除前**原地重绘**，避免基于过期列表误删 |

刷新语义：

- **仅由用户手动触发**。菜单打开期间**没有任何定时器 / 后台轮询**，不占用额外进程或线程，也不会在后台悄悄刷新。
- 刷新会**重新执行一次 `tmux` 查询**，拿到最新的附着状态与窗口数，并据此重算「附 N / 分 M」。
- tmux 管理器主视图的会话表格**不内嵌刷新行**（刷新属于全局动作，不伪装成会话数据行），刷新从底部动作条的 `r` 键进入；每次动作执行完毕回到循环顶部时也会自动重拉一次。
- **刷新是静默的**：成功路径不再输出任何 toast（原 `[OK] 正在重新获取会话列表 ...` 已删除），只有失败才提示。
- 删除流程的列表仍保留表格内 `⟳ 刷新会话列表` 行（删除危险操作前强制看最新列表，语义与二次确认独立）。
- 刷新后若已经没有可用会话，会给出告警（等价于「无可选会话」）。
- **对外契约不变**：仍返回带 `.Value` 的 `PSCustomObject` 或 `$null`；刷新项通过独立的刷新标记（`.IsRefresh` / 内部哨兵值）区分，不会与真实会话名混淆。

典型使用场景：

- 你在另一个终端标签页 `tmux attach` 了某个会话 → 回到本终端打开主视图 → `Esc` 进底部动作条按 `r` → State 列与「附 N / 分 M」立即更新。
- 刚用 `tmux kill-session` 删掉了会话，但列表还显示旧记录 → 刷新一次即可看到最新结果。
- 主流程里每次附着/新建/删除/直连结束都会**自动重拉**并重新弹出主视图，多数情况下无需手动刷新。

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
| `UI.GridViewFullScreen` | `$false` | `Out-ConsoleGridView` 是否全屏渲染（alternate screen buffer）。**2026-10-30 起默认 `$false`**：PSTui 1.0.5 内联渲染天然紧凑弹窗，避免 3~4 行的轻量菜单铺满全屏产生大面积黑底空洞；命令未暴露 `-Width`/`-Height` 尺寸参数（`Get-Command`/README 实测），需要沉浸式铺满可改回 `$true` |

## GridView 配色（Terminal.Gui `Scheme` 槽位）

主轨表格的配色由 [`Initialize-Config.ps1`](../../ShellPrompt/Private/Initialize-Config.ps1) 的 `UI.Theme` 域下发，落地逻辑在 [`Set-TgColorScheme.ps1`](../../ShellPrompt/Private/Set-TgColorScheme.ps1)：**就地改写** `SchemeManager` 里**已存在**的 `Base` / `Menu` 两个方案实例（不新增方案名、不写 `ThemeManager.Theme`——在 TG 2.4.10 上该组合会让内部字典与 `Theme` 失配）。

键 | 默认 | 说明 |
|----|------|------|
`UI.Theme.Enabled` | `$true` | `false` 时完全不触碰 Terminal.Gui 静态 API |
`UI.Theme.Name` | `@('Base','Menu')` | 覆写目标方案名（不存在时自动回退 `Base`）；单个字符串会被自动规范化为数组 |
`UI.Theme.Slots` | 见下表 | 槽位名 → `@{ Fg = 'R,G,B'; Bg = 'R,G,B' }` |

槽位（TG 2.4.10 上反射实测可写，共 10 个可视槽位；`Code*` 语法高亮槽位不参与菜单故不配置）：

槽位 | 默认色（Fg / Bg） | 作用 |
|------|--------|------|
`Normal` | `205,214,244` / `24,24,37` | 正文单元格、无焦点时的列头、列间竖线（Mocha Text + Base 统一暗底） |
`HotNormal` | `137,220,235` / `24,24,37` | 标题/表头/快捷键强调（Sky 冰青） |
`Focus` | `255,255,255` / `69,71,90` | **聚焦列头 + 表格有焦点时的选中行**（亮白字 + Surface1 高亮条） |
`HotFocus` | `166,227,161` / `69,71,90` | 其它 View 的聚焦热区（TableView 不读取） |
`Active` | `255,255,255` / `69,71,90` | **焦点不在表格时的选中行**（同 `Focus`） |
`HotActive` | `166,227,161` / `69,71,90` | 激活项热区（同 `HotFocus`） |
`Highlight` | `255,255,255` / `69,71,90` | 高亮标记（鼠标热区，与 `Focus` / `Active` 同色） |
`Editable` | `205,214,244` / `49,50,68` | 可编辑区（过滤框，正文字 + Surface0 深一档底） |
`ReadOnly` | `127,132,156` / `24,24,37` | 只读行（Overlay1 弱化灰紫） |
`Disabled` | `108,112,134` / `24,24,37` | 禁用行（Overlay0 暗灰） |

**迁移说明（Mocha 暗色分层配色，2026-10-30 起）**：本轮把 `UI.Theme.Slots` 从"满屏单一亮绿（137,209,133）+ 三档灰黑底"整体迁移到 Catppuccin Mocha 风格的暗色分层——正文用柔和灰白（Mocha Text）、强调用冰青（Sky）、选中行用亮白 + 蓝灰高亮条（Surface1）、禁用/只读自动退到灰紫（Overlay0/1），**所有槽位背景统一到 `24,24,37` 暗灰蓝底**，消除"全屏亮绿无层级 + 斑马纹"的观感：

- **两种焦点状态下的选中行高亮一致**（保留原不变量：`Focus` / `Active` / `Highlight` 三者完全相同）；
- **层级分明**：正文（灰白）/ 强调（冰青）/ 选中（亮白 + 高亮条）/ 禁用（暗灰）四个前景层级互不重叠；
- **过滤框可读**：`Editable` 用正文字色 + 深一档 Surface0 底，输入文字始终清晰。

> 只想自定义高亮色：改 `UI.Theme.Slots` 里的 `Focus` / `Active` / `Highlight`（三者保持完全相同），可任选底色。未知或不可写的槽位名会被静默跳过，不会报错。

## 能力说明（GridView 主轨的限制与补偿）

| 能力项 | GridView 主轨现状 | 补偿手段 |
|---|---|---|
| 行级红色 / 危险项高亮 | PSTui 未开放 Color/Theme API，且 TG TableView **不解析**单元格内的内联 ANSI SGR | `State` 列文本（`⚠ 危险` / `⚠ 备选` / `★ 最近`）承载语义；状态文本本身是纯字符串，**送入 Terminal.Gui 前**由 `ConvertTo-GridViewPlainText` 剥离可能混入的 SGR——转义字节会干扰 Wcwidth 宽字符列宽计算导致 `'⚠ 危险'` **吞空格**（2026-10-30 修复） |
| 底部帮助文本行 | 表格视图无底部帮助区 | 按键说明由 **PSTui 自带状态栏**（`Rows: n \| Enter Accept \| Esc Close`）提供；提示行草案 A.2 已于 2026-10-19 撤回——alternate screen 下菜单上方的提示用户看不到；仓库内 `Write-GridViewHint` 函数随之于 2026-10-29 一并删除 |
| 实时增量过滤 | 无键盘级过滤回调 | `-Focus Filter` 表格筛选框（`UI.GridViewFocus = 'Filter'`） |
| `Disabled` 行灰显 | 不支持渲染禁用态 | `State` 列标注 + 选中后**阻断**并提示 |
| 独立「退出」行 | 表格不再放 Exit 行 | `Esc` / `Ctrl-C` 退出，返回 `$null` |

> **2026-10-30 补充**：tmux 管理器底部是 Terminal.Gui `Shortcut` 快捷键栏（纯 TGUI 渲染，见 [tui-dashboard.md](tui-dashboard.md) §2）。表格视图（主机选择器等仍存活的 PSTui 视图）内的按键说明仍由 PSTui 自带状态栏提供。

## 性能特征（GridView 主轨）

| 维度 | `GridView` 主轨 |
|---|---|
| 渲染方式 | PSTui `Out-ConsoleGridView` 表格视图, 宿主内一次性重绘 |
| 每次按键重绘量 | 整表重绘, 由 TG 内部批处理 |
| 整屏清屏 | 无此机制 |
| 非交互终端 / stdin 重定向 | 分层处理：调用交互菜单前 `Assert-ConsoleUiReady` 检测到非交互宿主 → 抛**可定位终止错误**；若重定向绕过检测、`Out-ConsoleGridView` 运行时抛错 → 分发器**兜住异常**，`Write-Warning` 后返回 `$null`（不向调用方抛出） |
| 单个菜单项渲染耗时 | 不适用 (表格单元格) |

**结论**: 「ui 卡顿」问题已消解 —— 交互菜单**全部且仅**走 `GridView` 主轨, 逐行绝对定位覆盖的自研 ANSI 渲染实现已随降级轨一并移除, 相关的手写清屏、颜色表补全与三区布局代码均不再存在。2026-10-30 TUI 重构只调整了信息结构（tmux 管理器收敛为**一个**主视图 + 一行动作条），**未引入第二套渲染实现**。

> 真实交互终端的手感无法在自动化环境量化 (stdin 被重定向), 需人工验收：打开/移动/确认/取消各 1 轮、删除确认默认 `n`、空数据警告不弹窗。

## 删除会话的二次确认

[`Invoke-TmuxSessionDeletion`](../../ShellPrompt/Private/Invoke-TmuxSessionDeletion.ps1) 在选中会话后、`tmux kill-session` 之前插入 [`Read-SpectreConfirm`](../../Modules/PwshSpectreConsole/2.6.3/PwshSpectreConsole.psm1) 阻断式确认（默认答案 `n`）。确认不可用（非交互终端）时**按「不删除」处理**，绝不默认放行。
