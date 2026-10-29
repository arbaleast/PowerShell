> 本文件由根 AGENTS.md 路由触发加载。上级约束见根文件“三层边界”。

# 架构与目录规则

## 目录职责

- `Microsoft.PowerShell_profile.ps1`: **MUST ONLY** handle module loading, environment initialization, and startup configuration. **NEVER** put complex business logic here.
- `Public/`: Contains user-facing commands. MUST maintain stable command behavior, use clear PowerShell naming, and include help comments (`.SYNOPSIS`, etc.).
- `Private/`: Contains internal helper functions. **MUST NOT** be exposed to users.
- `ShellPrompt/Settings.ScriptAnalyzer.psd1`: PSScriptAnalyzer configuration. MUST be kept in sync with actual code conventions.

## 兼容性与降级（Compatibility & Fallbacks）

- Prefer feature detection over version checking.
- 模块最低版本由 `ShellPrompt.psd1` 的 `PowerShellVersion` 统一把守, 代码内**不再**做 PS 5.1 分支。
- `PwshSpectreConsole` 是**硬依赖** (不是可选依赖): 加载失败时 `ShellPrompt.psm1` 直接 `throw`, 不做静默降级。
- 交互菜单是**单轨制** (2026-10-18 起移除自研 ANSI 降级轨), 唯一渲染实现是 `Modules/PSTui` 的 `Out-ConsoleGridView` (由 `Private/Invoke-GridViewMenu.ps1` 实现):
  - `Private/Get-ConsoleUiBackend.ps1` 的 `Get-ConsoleUiBackend` 只做**主轨可用性检测** (PSTui 可发现性 / 命令来源冲突 / `Terminal.Gui` 主版本争用 / 交互式宿主), 其中 `Backend` **恒为** `'GridView'`。
  - **检测是惰性的** (2026-10-18 起): 模块加载期**不执行**检测 (实测是模块导入阶段最大单一热点, 约 500ms, 启动期用不到), 改由 `Get-ConsoleUiState` 在首次真正需要时现场检测一次并缓存到 `$script:ConsoleUiBackend`, 后续复用。
  - 检测自身的实现成本也已优化: 模块可发现性用目录级查找 (`Get-ConsoleUiModuleOnDisk`) 替代 `Get-Module -ListAvailable`, 同名命令来源用 `Get-Command -ListAvailable` (去掉 `-All`, 避免全量模块元数据装载) —— 四项诊断语义保持不变。
  - **Phase 1 启动图缓存** (2026-10-18 起): 依赖闭包的解析结果缓存到 `$env:LOCALAPPDATA\ShellPrompt\startup-graph.json`; 下次启动校验所有参与文件的 `(LastWriteTimeUtc, Length)` 未变则命中缓存, 跳过索引 + AST 解析。缓存损坏 / 解析失败 / 写失败一律**静默回退**到全量重建, 不影响启动。
  - `Show-HostSelector` / `Show-SessionManager` / `Show-TmuxSessionList` 是纯分发器, 调用实现前统一执行 `Assert-ConsoleUiReady -Feature <功能名>`。
  - `PSTui` 缺失 / 版本冲突 / `Terminal.Gui` 主版本争用 / stdin 被重定向 → `Assert-ConsoleUiReady` 抛出**可定位的终止错误** (含功能名与原因), **不再静默降级到其它渲染实现**。
  - 调用方 (如 `Start-TmuxSession`) 不感知渲染实现差异, 分发器已无 `-Backend` 参数。

### PSTui TableView 留白约束 (P1.7, 2026-10-19 记录)

- 真机截图观察到的"表格下方大量黑色留白" + 底部状态栏 ("Rows: N | Enter Accept | Esc Close") + 出格式节奏 `Rows.Count < 终端高 - 标题/状态条占用` 的场景下, PSTui `Out-ConsoleGridView` (底层 TG v2 `TableView`) **默认填满分配高度, 不按行数收缩**。
- 调研路径:
  - **改 PSTui 内部 `TableView.Style` 或 `ColumnStyle.Width`** (反射改 readonly 字段): 风险中-高, 依赖 TG IL 行为, 升级即破; 现状决定**不实施**。
  - **弹窗前底部追加状态栏**: 弹窗后 alternate screen buffer 会把 stdout 隔离, 退出后 Spectre 输出会留下, 但同一会话内用户**看不到**, 等于无效; **不实施**。
  - **PromptWrapper / `Restore-GridViewSelection` 限制可见列宽**: PSScriptAnalyzer 已识别的公开层不暴露列宽参数, 改这条路等同于反射, 风险等价; **不实施**。
- 结论: PSTui TableView 的"行少时下方留白"是**上游行为约束**, 不在 `ShellPrompt/` 模块可控范围。任何"修复留白"的尝试都属于本项目边界外, 不进入版本控制。
- 实施纪律: `Private/` 内**禁止**新增/修改 PSTui 反射代码 (`TableView.Style` / `ColumnStyle.Width` 等 readonly 字段硬写)。如未来 PSTui 暴露相关公开参数, 再单独评估。

### GridView 主题配色 (2026-10-18 起)

- `UI.Theme.Slots.Focus` / `Active` / `Highlight` 均为 **亮绿字 (`137,209,133`) + 稍亮底 (`40,40,40`)** —— 与 `Normal` (`137,209,133`/`30,30,30`) 相比仅底色亮度差 1 级, 列头与正文均为绿字, 整张表与绿主题统一; 同时保留 v2.1 的不变量"两种焦点状态下的选中行高亮一致"。
- `UI.Theme.Slots.Editable` 为 **亮绿字 (`137,209,133`) + 近黑底 (`20,20,20`)** —— 过滤框在焦点态下用暗底承托绿字, 输入文字始终清晰可读。
- `HotFocus` / `HotActive` (其他 View 的聚焦热区, TableView 不读取) 仍保留 v2.1 的浅色不变 —— 它们不影响 GridView 视觉, 改它们属于无收益改动。
- 详见 [`README.md`](../README.md) 的「GridView 配色 (Terminal.Gui `Scheme` 槽位)」与 [`ShellPrompt/CHANGELOG.md`](../ShellPrompt/CHANGELOG.md) 的 `[Unreleased] / Changed` 条目。

## 启动期时序 (2026-10-18)

profile 加载分为 3 个阶段, 各阶段目标与耗时归因:

| 阶段 | 内容 | 关键耗时 (本仓库现状) | 是否可优化 |
|---|---|---|---|
| 阶段 1 (欢迎语) | dot-source banner 链路 + 启动图缓存命中 | ~330ms (含文件 IO) | 已优化 (Phase 1 启动图缓存) |
| 阶段 2 (延迟初始化同步路径) | Invoke-DeferredInit: fnm (走缓存) + starship (同步 init, `-join "``n"` 后 iex) + PSReadLine import + set options | ~520ms + ~365~453ms (starship init 子进程) | starship init 是 profile 期最大单一开销 (回退到 P3 优化前的同步路径; PS 7.6+ 下 `&` 捕获的多行输出必须先 join 成单字符串再 `Invoke-Expression`, 否则参数绑定器拒收, 详见 `CHANGELOG.md` `[Unreleased] / Fixed`) |
| 阶段 3 (Import-Module ShellPrompt) | dot-source 30 Private (移除 5 个 wttr 相关后) + 加载 PwshSpectreConsole + 用户配置 | ~960ms (估) | **不可动** (AGENTS.md 红线 + 架构级变更) |

**Starship 同步 init**: 阶段 2 `Invoke-DeferredInit` 同步执行 `starship init powershell --print-full-init` (约 365~453ms 子进程), 由 starship 自身替换 `Function:prompt` 完成接管. 历史 P3 优化方案 (由 `Register-WttrPromptWrapper` wrapper 惰性触发 `Initialize-StarshipLazy`) 已随方案 B 部分回退一并移除, 详见 `CHANGELOG.md` `[Unreleased] / Removed`.

**fnm env 缓存**: 阶段 2 `Invoke-DeferredInit` 调 `Initialize-FnmEnvironment`. 首次或 fnm.exe / node 版本列表变化时跑一次 `fnm env` 子进程并写 `$env:LOCALAPPDATA\ShellPrompt\fnm-env.json`; 后续启动直接读缓存 + 重算 PATH. **PATH 永不缓存** (避免静默覆盖用户临时 PATH 修改). 保底路径: 解析 aliases 目录失败时回退到同步执行 `fnm env` 子进程.

## 配色体系

本节是所有配色键 / Scheme 槽位 / 渲染层取色关系的速查表, 单轨 PSTui 时代 (2026-10-18 起) 的唯一权威描述。任何颜色改动先查这里再动手。

### Colors 域（`$config.Colors.*`, 14 键）

全部定义见 [`Private/Initialize-Config.ps1`](../../ShellPrompt/Private/Initialize-Config.ps1) `Colors = [ordered]@{...}`, 值为带 ESC 的 ANSI 转义串, 渲染时由 `Get-CachedConfig -Section Colors -Key <键>` 命中 `$script:ColorCache` 快路径。

| 类别 | 键名 | RGB 默认 | 消费方 | 备注 |
|---|---|---|---|---|
| 主绿色系 | `FreshGreen` | 137,209,133 | Tables / 状态行 / TG Scheme `Normal/Focus/Active/Highlight/Editable` | 表格正文主色 |
| 主绿色系 | `SageGreen` | 159,177,159 | TG Scheme `HotNormal/ReadOnly` | 弱化绿, 热区与只读行 |
| 灰阶层 | `DarkGray` | 50,50,50 | 备用 | 当前渲染层未消费 |
| 灰阶层 | `MidGray` | 100,100,100 | TG Scheme `Disabled` | 禁用态 |
| 灰阶层 | `LightGray` | 180,180,180 | 备用 | 当前渲染层未消费 |
| 灰阶层 | `White` | 255,255,255 | 备用 | 当前渲染层未消费 |
| 标题色 | `Cyan` | 112,199,209 | Title 区主色 / wttr 后缀拼接 | 仅一条路径消费 |
| 死代码 | `Danger` | 220,90,90 | 未消费 | PSTui 不支持行级配色, 已定义未用 |
| 死代码 | `Warning` | 220,180,80 | 未消费 | 同上, 用 `⚠` 符号代替 |
| 死代码 | `SelectedBg` | 112,199,209 底 + 近黑字 | 未消费 | TG Scheme `Focus` 已接管高亮 |
| 暗背景 | `BgDarker` | 40,40,40 | TG Scheme 多个槽位底 | 表格基色一致 |
| 复位 | `Rst` | (重置 ESC `\e[0m`) | 全部 Spectre / ANSI 输出末尾 | 必需, 漏写颜色泄漏 |
| 强调 | `Bold` | `\e[1m` | 备用 | 当前渲染层未消费 |
| 弱化 | `Dim` | `\e[2m` | `Write-GridViewHint` 提示行外层 | 唯一显式消费 |

总计：消费中 **8 键**（FreshGreen / SageGreen / MidGray / Cyan / BgDarker / Rst / Dim + 列头走 `Colors.*` 的间接消费 Bold） / 死代码 **3 键**（Danger / Warning / SelectedBg, 待 PSTui 支持行级配色前不会复活）/ 备用 **3 键**（DarkGray / LightGray / White）。

### UI 域 / `Theme.Slots`（10 槽位）

定义见同上 `Initialize-Config.ps1` `UI.Theme.Slots`, 键 = TG `Terminal.Gui.Drawing.Scheme` 的**反射实测可写**的属性名 (TG 2.4.10.0), 值 = `@{ Fg = 'R,G,B'; Bg = 'R,G,B' }`。

| Scheme 槽位 | 用途 | 引用 Colors 键 |
|---|---|---|
| `Normal` | 正文单元格 / 无焦点列头 / 列间竖线 | FreshGreen + 暗背景 |
| `HotNormal` | 快捷键热区 | SageGreen |
| `Focus` | 聚焦列头 / 有焦点时选中行 | FreshGreen + BgDarker |
| `HotFocus` | 其他 View 的聚焦热区 (TableView 不读取) | — |
| `Active` | 无焦点时选中行 | FreshGreen + BgDarker |
| `HotActive` | 激活项热区 (TableView 不读取) | — |
| `Highlight` | 高亮标记 | FreshGreen + BgDarker |
| `Editable` | 过滤框输入区 | FreshGreen + 近黑底 |
| `ReadOnly` | 只读行 | SageGreen |
| `Disabled` | 禁用行 | MidGray |

> **新契约 (2026-10-18)**: `Focus` / `Active` / `Highlight` 三个槽位**必须取同一颜色** (`137,209,133` + `40,40,40`), 否则"焦点在表格"与"焦点在过滤框"两种状态下选中行高亮不一致, 且 IL 级实测确认 Focus 被聚焦列头和"有焦点时选中行"**共用**。

实际装配入口: [`Private/Set-TgColorScheme.ps1`](../../ShellPrompt/Private/Set-TgColorScheme.ps1)；幂等性 / 翻转防护 / TG 字典失配修复 详见该文件头部关键实现决策。

### 渲染层现状

- **PSTui `Out-ConsoleGridView` 不支持 per-row 染色** (TG v2 TableView 也没暴露 `ColumnStyle.ColorGetter` 的轻量入口)。语义靠 State 列文本承担: `●` 已附着 / `⚠` 危险 / `⚠` 备选 / `✗` 不可用。
- 行级配色的 路线 α (反射 TG `ColumnStyle.ColorGetter`) 已实测可行但风险高 (依赖 TG IL 行为, 升级即可能破), 当前**未启用**, 留作 P1 候选。
- 5 行 / 3 类菜单 (SSH 主机 / tmux 管理 / tmux 会话) 共享同一套 `Focus == Active == Highlight` 语义, 因此配色改动只需调整 `UI.Theme.Slots` 一处。

### 主题切换约束

- TG `ThemeManager.Theme` 字典是配置驱动的, "新增 Scheme 名 + 设 `Theme`" 这条看似标准的路径会破坏 `SchemeManager` 内部状态 (后续 `GetScheme` 全部抛异常)。Set-TgColorScheme 采取**就地覆写 `Base` / `Menu` 已存在实例**的策略, 刻意不新增方案名、不写 `ThemeManager.Theme`。
- 当前是**单主题** (`UI.Theme.Slots` 只一份), 不引入多主题 — 避免 TG 字典失配。
- 颜色微调只需改 `Colors` 域键值；Scheme 槽位翻转只需改 `UI.Theme.Slots` 里的 `Fg/Bg`。

### wttr 标题区配色

- Title 主色: 走 TG `Base.Focus` 与 `Menu.Normal` (由配色体系接管), 不直接读 `Colors.Cyan`。
- wttr 描述色: 客户端字典翻译后由 [`Private/Get-WttrTitleSuffix.ps1`](../../ShellPrompt/Private/Get-WttrTitleSuffix.ps1) 拼到 Title 末尾, 不做染色 (保留文本可读性, Title 区由 TG 配色统一)。
- 温度色: 同上。

## 提示符 wrapper（2026-10-18 起已移除）

本项目**不接管** `Function:prompt`. 历史版本中的模块侧 [`Private/Register-WttrPromptWrapper.ps1`](../../ShellPrompt/Private/Register-WttrPromptWrapper.ps1) (含 starship lazy init / 锚点替换 / 底部 ASCII 栏拼接) 已于 2026-10-18 整体移除 (含配套 3 个 Pester 文件 + 4 个 Private 工具函数 + `Initialize-StarshipLazy.ps1`), 详见 [`CHANGELOG.md`](../../ShellPrompt/CHANGELOG.md) `[Unreleased] / Removed`. 用户的 prompt 由 starship 原生接管 (`profile 阶段 2` 同步执行 `$starshipInit = & $starship init powershell --print-full-init; Invoke-Expression ($starshipInit -join "`n")`, PS 7.6+ 必须先 join), 提示符样式不受本项目约束.

**`Microsoft.PowerShell_profile.ps1` 的边界**: profile 始终**仅**做模块加载 + 环境初始化 + 启动配置, 不持有任何 wttr 业务代码 (符合 AGENTS.md 的"profile 不放业务逻辑"原则).

## 交互菜单 PSTui 标题区天气（2026-10-18 起, 方案 R2）

三个交互菜单 (SSH 主机选择器 / tmux 管理器 / tmux 会话列表) 的 PSTui 窗口**标题区**自动追加一行 wttr 天气短串 (如 `Shanghai: 🌫 +18°C`), 顶部居中显示. 渲染入口在 [`Private/Invoke-GridViewMenu.ps1`](../../ShellPrompt/Private/Invoke-GridViewMenu.ps1) 的三个 `Invoke-GridViewPrompt` 调用点 (`Invoke-GridViewHostSelector` / `Invoke-GridViewSessionManager` / `Invoke-GridViewSessionList`):

- 在拼装 `-Title` 参数之前, 用一段 6 行模板 (判定 `$script:Config.Weather.Enabled` + `Get-WttrWeather -Format Short -CacheMinutes 10 -ErrorAction SilentlyContinue`) 计算 `$wttrSuffix`;
- 启用且 wttr 非空时, 把 ` - <wttr>` 拼到原标题末尾; 否则 `$wttrSuffix` 留空, 标题原样渲染;
- `Get-WttrWeather` 自带超时/失败兜底(返回 `''`), 此处再加 `IsNullOrWhiteSpace` 兜底, 永不抛异常, 永不破坏 PSTui 标题;
- 数据源: [`Private/Get-WttrWeather.ps1`](../../ShellPrompt/Private/Get-WttrWeather.ps1) (`$script:_WttrCache` 缓存键 = `"Format|Url"`);
- 副作用: `Write-GridViewHint` 已**不再**渲染天气片段 (上一轮挂在提示行末尾的逻辑已撤掉), 避免与标题区重复显示; 函数回到只渲染按键提示的纯职责.

`Weather` 配置域已收缩为只 `Enabled` 布尔 (历史 7 键已随 wrapper 全链路移除):
