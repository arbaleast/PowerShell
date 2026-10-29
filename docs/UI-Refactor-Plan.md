# UI 层重构设计方案：参考 Microsoft.PowerShell.ConsoleGuiTools 重构界面层

> **文档版本**: v1.1（已实施，正文 1~附录 B 为历史设计稿，结论已被「附录 C: 实施结果归档」取代）
> **创建日期**: 2026-10-17
> **目标**: 为 ShellPrompt 模块的 UI 层提供一份完整的重构设计与实施方案
> **约束**: 本文档为纯设计/规划任务，不修改任何 .ps1 代码

> ## ⚠️ 实施状态横幅（v1.1 新增）
>
> 本文正文（§1~附录 B）是**选型调研阶段的历史稿**，写于 `Microsoft.PowerShell.ConsoleGuiTools` 时代。
> 三轮实测选型后结论已改，并且**已实施完毕**。请以 [附录 C](#附录-c实施结果归档) 为准，正文里「方案 A：不迁移」等结论**已作废**。
>
> 三处必须更正的事实错误：
>
> 1. **菜单从来不是用 Spectre.Console 渲染的。** `Show-HostSelector` / `Show-SessionManager` 一直是**自研 ANSI 转义序列 + `Invoke-MenuMachine` 键盘状态机**。Spectre.Console 只负责 spinner / 进度动画（`Show-ProgressSpinner` / `Invoke-WithProgress`）和本次新增的提示行 / 删除确认。正文多处「菜单 Spectre 轨 / Legacy ANSI 轨」的说法是把进度动画的双轨误套到了菜单上。
> 2. **不再有 PS 5.1 轨。** v2.0 已取消 5.1，`ShellPrompt.psd1` 的 `PowerShellVersion` 先后抬到 `7.4`，本次因 `PSTui`（.NET 10 二进制模块）再抬到 **`7.6`**。正文中所有「PS 5.1 / Legacy」的路线讨论均已过期。
> 3. **`Microsoft.PowerShell.ConsoleGuiTools` 已归档并从仓库中删除**，社区续作是 **`PSTui` 1.0.5**（`Modules/PSTui/1.0.5/`，构建于 Terminal.Gui v2）。`ConsoleMonster` / `PoshTui` / `PsUi` 同样已删除。

> ## ⚠️ 实施状态横幅（v2.4 精简轮次新增）
>
> 本文件整体是**历史方案快照**。正文（§1~附录 B）写于选型调研阶段，其中的组件描述、测试用例数量、调用点统计与文件路径**可能与当前实现不一致**；**当前状态一律以 [`ShellPrompt/CHANGELOG.md`](../ShellPrompt/CHANGELOG.md) 与 [`README.md`](../README.md) 为准**。本文保留原文仅作决策留档，不再逐条追改。
>
> v2.4 精简轮次已删除下列**零生产调用方**的组件，正文凡引用它们之处**均已失效**（文中相关段落已就地加注）：
>
> - `Private/Show-InputPrompt.ps1`（连同 `Update-InputBuffer` / `Test-InputValidation`）
> - `Private/Get-KeyboardFilter.ps1`
> - `Private/Start-SshInteractive.ps1`
> - `Private/Get-SshSocketPath.ps1`
> - `Invoke-MenuMachine.ps1` 中的 `ConvertTo-CsiArrowKey` 函数
>
> 对应用例（`Show-InputPrompt` / `Update-InputBuffer` / `Test-InputValidation` / `Test-FilterCharacter` / `Get-FilteredItems` / `Update-FilterString` / `ConvertTo-CsiArrowKey`）已同步删除；`Get-KeyboardFilter` 的过滤逻辑已内联进 `Invoke-MenuMachine.ps1` 的 `Get-VisibleMenuItems`。
>
> 另有两处口径变化：**①** `Invoke-WithProgress` 的生产调用点为 **3 处**（全部同步路径、未传 `-PollScript`），文中「4 处生产调用」已过时；**②** v2.1 起轮询封装**不再自绘 spinner**，`Show-ProgressSpinner` 当前无生产调用方。
>
> ### ⚠️ §1 现状盘点表已整体失效（2026-10-18）
>
> 自 2026-10-18 起，**自研 ANSI 降级轨（AnsiFallback）已整体移除**，控制台 UI 只剩 **PSTui GridView 一条轨**。因此下表 §1.1 函数总览中下列条目**均已不存在**，表中所有相关描述**一律失效**：
>
> - `Private/Invoke-ConsoleMenu.ps1` / `Private/Invoke-AnsiMenu.ps1`
> - `Private/Invoke-MenuMachine.ps1`（含 `Send-MenuKey` / `ConvertTo-CsiArrowKey` / `Get-VisibleMenuItems`）
> - `Private/Write-MenuItem.ps1`（含 `New-MenuItem`）
> - `Private/New-AnsiLayout.ps1`（含 `Add-MainLine` / `Set-FooterLine` / `Write-AnsiLine`）
> - `Private/Clear-AnsiScreen.ps1`
> - `Private/New-StatusBadge.ps1`（含 `Format-StatusBadge`）
> - `Private/New-DynamicHelpPanel.ps1`（含 `Get-SessionActionHelp`）
> - `Private/Get-TmuxSessionMenuOption.ps1`
> - `Private/Get-KeyboardFilter.ps1` / `Private/Show-InputPrompt.ps1`
>
> **当前实现**：三个交互菜单（`Show-HostSelector` / `Show-SessionManager` / `Show-TmuxSessionList`）统一为纯分发器，渲染由 [`Private/Invoke-GridViewMenu.ps1`](../ShellPrompt/Private/Invoke-GridViewMenu.ps1) 与其配套行构造/列裁剪/选中归一化函数承担；主轨不可用时由 `Assert-ConsoleUiReady` 抛出**可定位的终止错误**，**不再静默降级**。请以 [`ShellPrompt/CHANGELOG.md`](../ShellPrompt/CHANGELOG.md) 与 [`README.md`](../README.md) 为准。

---

## 1. 现状盘点表

> 以下盘点基于对全部 13 个 UI 函数文件的逐一阅读，不含猜测。

### 1.1 函数总览

| # | 文件路径 | 当前实现手段 | 交互模型 | 调用方（谁调用它） | 测试覆盖 | 已知痛点 |
|---|----------|--------------|----------|-------------------|----------|----------|
| 1 | `Private/Invoke-ConsoleMenu.ps1` | `[Console]::Write` + ANSI 转义序列 (`\e[Line;H`) | 键盘上下导航 / Enter 确认 / Q 退出 / 实时描述行更新 | **调用方**: 旧版本直接调用（目前 Show-HostSelector/Show-SessionManager 已迁移到 Invoke-MenuMachine，Invoke-ConsoleMenu 保留作为向后兼容路径） | **无直接测试** | ① VSCode 集成终端下 `WindowHeight` 返回 0，导致垂直居中失效回退到 `originY=1`；② PS 5.1 不支持 `` `e`` 转义序列（代码中已用 `[char]27` 兼容但仍有边界问题）；③ 整屏 `Clear()` 后重绘存在闪烁感；④ `ReadKey` 在非交互式终端（重定向/PSRP）下抛异常被 catch 后直接 return `$null`，调用方拿不到有意义的错误 |
| 2 | `Private/Invoke-MenuMachine.ps1` | `Send-MenuKey` 状态机 + `ConvertTo-CsiArrowKey` CSI 序列三字节重组〔v2.4：`ConvertTo-CsiArrowKey` 已删除，CSI 重组内联至 `Invoke-MenuMachine` 主循环〕 + `New-AnsiLayout` / `Write-MenuItem` / `New-StatusBadge` 渲染委托 | 四状态机: Idle / Selecting / Filtering / Inputting；键盘事件分发入口 | **调用方**: `Show-HostSelector`、`Show-SessionManager` | **有测试**: `ShellPrompt.Tests.ps1` 覆盖 `Send-MenuKey`（CSI 重组后 UpArrow/DownArrow 导航、ESC 退出）、`ConvertTo-CsiArrowKey`（8 个 case 覆盖方向键/非法字节/真 ESC）〔v2.4 精简轮次：该函数已删除，对应用例同步删除〕、`Invoke-MenuMachine v5.4`（VK→ConsoleKey 映射表、StrictMode 容错） | ① PS 5.1 `ConsoleKeyInfo` 跨 `& $mod {}` 边界后 `.Key`/`.Character` 字段被 .NET 反射层置空（PSObject 包装导致）；② CSI 三字节序列重组逻辑复杂（`pendingEscape` + `csiBuffer` 状态机）；③ PS 7.6.3 + Windows Terminal 下 `ReadKey` 返回的 `KeyInfo.Key` 字段为 `$null`，需回退到 `VirtualKeyCode` 映射 |
| 3 | `Private/Write-MenuItem.ps1` | `New-MenuItem` 纯数据构造 + `Write-MenuItem` 返回 ANSI 字符串 | 三视觉态: Selected（反色高亮 + ▶）/ Normal（弱化色）/ Disabled（暗灰 + 斜杠）；Severity（Normal/Warning/Danger）映射颜色 | **调用方**: `Show-HostSelector`、`Show-SessionManager`、`Invoke-MenuMachine` | **有测试**: `ShellPrompt.Tests.ps1` 覆盖 `New-MenuItem`（5 个 case）和 `Write-MenuItem`（8 个 case：序号/选中/禁用/描述/Index 不同输出不同序号） | ① Badge 字段使用 `>` 字符（ASCII）与设计系统中的 Unicode 箭头不完全一致；② `-OriginX` 参数用于居中 padding，调用方需手动计算 |
| 4 | `Private/Show-HostSelector.ps1` | 委托 `Invoke-MenuMachine` + `New-MenuContext` + `New-MenuItem` + `New-StatusBadge` + `New-AnsiLayout` | 实时键盘过滤（Q1=A 逐字过滤）+ LastHost 置顶（绿色徽章）+ SSH config Host→HostName 映射显示 | **调用方**: `Start-TmuxSession` | **无直接测试**（通过 Invoke-MenuMachine 间接覆盖） | ① 诊断路径依赖 `$script:Config.SSH.LastHost`；② SSH config 解析使用正则 `^Host\s+` 和 `^\s+HostName\s+`，对多行 HostName/别名支持有限 |
| 5 | `Private/Show-SessionManager.ps1` | 委托 `Invoke-MenuMachine` + `New-MenuContext` + `New-MenuItem` + `New-DynamicHelpPanel` + `New-AnsiLayout` | 动态帮助面板（Footer 根据选中动作切换）+ Severity（Danger=删除/Warning=直连） | **调用方**: `Start-TmuxSession` | **无直接测试**（通过 Invoke-MenuMachine 间接覆盖）；诊断补丁写入 `$env:TEMP\shellprompt_ssm_error.log` | ① 诊断补丁用 `Write-Host` 异常输出（`##SSM-ERROR##`），违反 AGENTS.md 中"UI 渲染用 Write-Host 允许"的例外规则；② 会话为空时动态隐藏"附着/删除"项，但布局高度已在 `New-AnsiLayout` 时计算好，可能导致空白区域 |
| 6 | `Private/Show-InputPrompt.ps1` | `[Console]::ReadKey` 逐字符读取（主路径）+ `Read-Host` 降级（备用） | 状态机: Continue / Submit / Cancel；支持 Backspace / Ctrl+U / Ctrl+C / Esc 取消；`Update-InputBuffer` + `Test-InputValidation` 纯函数分离 | **调用方**: `Start-TmuxSession`（会话名输入） | **有测试**: `ShellPrompt.Tests.ps1` 覆盖 `Update-InputBuffer`（7 个 case）和 `Test-InputValidation`（8 个 case）〔v2.4 精简轮次：`Show-InputPrompt.ps1` 已删除，两组用例同步删除〕 | ① `[Console]::ReadKey` 在非交互式终端失败后降级到 `Read-Host`，丢失 Secret 模式（密码不回显）；② `Secret` 模式用 `*` 替代显示，但未实现真正的安全隐藏（明文仍在内存）；③ PS 5.1 `[Console]::ReadKey` 在某些控制台模式下行为不一致 |
| 7 | `Private/New-WelcomeBanner.ps1` | 纯函数返回 `string[]` 行数组，`Get-RandomQuote` 带 mtime 缓存 | 静态布局（9 行）：标题 / 空 / ~ / 语录 / 时间 / 空 / ~ / 分割 / 空 | **调用方**: `Show-UserScoopLogo`（Public） | **有测试**: `ShellPrompt.Tests.ps1` 覆盖 `New-WelcomeBanner`（6 个 case）和 `Get-RandomQuote`（4 个 case：空路径/文件不存在/有效文件/mtime 缓存） | ① 语录文件不存在或解析失败时 fallback 为 `SYSTEM READY`，但无日志输出；② 宽度默认 60，最小 40，固定 9 行布局不适配短终端；③ 时间戳精度到秒，每次 profile 加载都变化，无法被 mtime 缓存（mtime 缓存只针对语录内容） |
| 8 | `Private/New-StatusBadge.ps1` | 纯数据构造器返回 PSCustomObject + `Format-StatusBadge` ANSI 字符串渲染 | 七状态: Online（绿●）/ Attached（蓝●）/ Detached（灰○）/ NetworkError（红✗）/ Pending（黄◐）/ Warning（黄!）/ Disabled（暗×） | **调用方**: `Show-HostSelector`（LastHost 徽章）、`Show-SessionManager`（Header 徽章）、`New-WelcomeBanner`（可嵌入 HeaderBadges） | **有测试**: `ShellPrompt.Tests.ps1` 覆盖 `New-StatusBadge`（7 个状态 case）和 `Format-StatusBadge`（3 个 case） | ① 蓝色（`$blue`）和黄色（`$yellow`）/ 红色（`$red`）在 `Initialize-Config.ps1` 的 Colors 域中**硬编码**，不在用户可配置 Colors 域中；② 默认 Glyph 使用 Unicode 符号，在不支持 Unicode 的终端可能显示为方块 |
| 9 | `Private/New-AnsiLayout.ps1` | `New-AnsiLayout` 构造三区布局对象 + `Write-AnsiLine` / `Show-AnsiLayout` 渲染 + `Add-MainLine` / `Set-FooterLine` 修改 | 三区: Header（4 行：空/标题/空/分割）/ Main（可变）/ Footer（2 行：分割/空）；支持水平 + 垂直双居中 | **调用方**: `Show-HostSelector`、`Show-SessionManager` | **有测试**: `ShellPrompt.Tests.ps1` 覆盖 `New-AnsiLayout`（6 个 case）、`Add-MainLine/Set-FooterLine`（4 个 case）、`Write-AnsiLine`（函数存在性验证） | ① `[Console]::WindowWidth/Height` 在 VSCode 集成终端/SSH/headless 下返回 0 或不可靠值，已有多层 fallback 但仍有边界；② `Show-AnsiLayout` 每次调用都 `Clear()` 整屏，不支持增量重绘；③ Center 模式下 `OriginX` 依赖 `CenterWidth=100` 作为内容宽度假设 |
| 10 | `Private/New-DynamicHelpPanel.ps1` | 纯函数返回拼接 ANSI 字符串 | 接收 `HelpEntry[]`（Keys + Action），用 `│` 分隔拼接 | **调用方**: `Show-SessionManager` | **有测试**: `ShellPrompt.Tests.ps1` 覆盖 `New-DynamicHelpPanel`（4 个 case）和 `Get-SessionActionHelp`（4 个 case） | ① `Get-SessionActionHelp` 中硬编码了"附着/恢复"、"删除"、"刷新"等 Label 字符串，与 `Show-SessionManager` 中的菜单项 Label 紧耦合；Label 改名将导致帮助面板失效 |
| 11 | `Private/Invoke-WithProgress.ps1` | 双轨制: Spectre 路径（`Invoke-SpectreCommandWithStatus`） + Legacy 路径（`Show-ProgressSpinner` 循环）〔v2.0：Legacy 路径已删除；v2.1：轮询路径不再自绘 spinner〕；`Invoke-WithProgressSpectre` 封装 | 支持: ScriptBlock 执行 / PollScript 轮询 / TimeoutSeconds 超时 / SuccessMessage / FailureMessage / SuppressConsole | **调用方**: `Start-TmuxSession`（4 处生产调用：SSH 探测 x2 / 会话刷新 x2）〔v2.4 校正：实为 **3 处**调用，且全部为同步路径、未传 `-PollScript`〕 | **有测试**: `ShellPrompt.Tests.ps1` 覆盖同步模式（返回值/异常透传）、轮询模式（立即完成/超时/PollScript 异常）、`Frames` 数组记录 | ① Spectre 路径**不支持硬超时**（`Spectre.Console.Start-AnsiConsoleStatus` 自身无 timeout），调用方需要超时保护时必须 fall back legacy；② `-PollScript` 参数与 Spectre 路径互斥（路由规则短路求值）；③ 双轨制路由在模块加载时通过 `Test-SpectreSpinnerAvailable` 探测，后续不支持动态切换 |
| 12 | `Private/Show-ProgressSpinner.ps1` | 双轨制: Legacy（`Show-ProgressSpinnerLegacy`〔v2.0：该 Legacy 路径已删除〕） + Spectre（`Show-SpectreProgressSpinner`）+ `Get-SpinnerFrame/SpinnerSequence/Test-SpectreSpinnerAvailable/Get-SpinnerStyleMapping` 纯函数 | 五样式: Braille（⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏）/ Ascii（-\|/）/ Blocks（▁▂▃▄▅▆▇█▇▆▅▄▃▂）/ Dots（6 位置）/ Arrows（8 方向） | **调用方**: `Invoke-WithProgress`（内部使用） | **有测试**: `Show-ProgressSpinner.Tests.ps1` 覆盖帧循环（10 帧 Braille）、帧回绕（Frame=10→0）、双轨制路由（7 个 case） | ① PS 5.1 不支持 `` `e`` 转义序列（已用 `[char]27` 兼容），但 `Get-CachedConfig` 预热的颜色值中硬编码了 `` `e`` 字符串；② 帧动画在快速系统上可能帧率过高（无 min frame time 控制）；③ `Test-SpectreSpinnerAvailable` 在 PS 5.1 下返回 `$false`，但模块加载时 PwshSpectreConsole 尝试导入失败后只写 `Write-Verbose`，不提示用户 |
| 13 | `Public/Show-UserScoopLogo.ps1` | 委托 `New-WelcomeBanner` + `Get-RandomQuote` + `Write-Host` 输出 | 静态 Banner 输出，无交互 | **调用方**: `Microsoft.PowerShell_profile.ps1`（Phase 1 dot-source 调用） | **无直接测试** | ① `Write-Host` 输出（AGENTS.md 例外允许）；② 固定宽度 49 字符，与 `New-WelcomeBanner` 默认 Width=60 不一致；③ profile 阶段执行，无法利用模块加载时的 `$script:ColorCache`（因为是先 dot-source 再 Import-Module） |

### 1.2 测试覆盖矩阵

| 测试文件 | 覆盖的 UI 函数 | 测试数量 | 覆盖率说明 |
|----------|----------------|----------|------------|
| `ShellPrompt.Tests.ps1` | `New-MenuItem`, `Write-MenuItem`, `New-StatusBadge`, `Format-StatusBadge`, `New-DynamicHelpPanel`, `Get-SessionActionHelp`, `New-AnsiLayout`, `Add-MainLine`, `Set-FooterLine`, `Write-AnsiLine`, `Get-SpinnerFrame`, `Get-SpinnerSequence`, `Invoke-WithProgress`, `New-WelcomeBanner`, `Get-RandomQuote`, `Update-InputBuffer`, `Test-InputValidation`, `Send-MenuKey`, `ConvertTo-CsiArrowKey`, `Invoke-MenuMachine` | ~50 个 It 块 | 覆盖所有纯函数和状态机核心路径〔v2.4：`Update-InputBuffer` / `Test-InputValidation` / `ConvertTo-CsiArrowKey` 相关用例已删除〕 |
| `Show-ProgressSpinner.Tests.ps1` | `Show-ProgressSpinner`（双轨制路由）、`Invoke-WithProgress`（集成） | ~20 个 It 块 | 覆盖帧循环、回绕、双轨制路由、轮询、超时 |
| `Get-WttrWeather.Tests.ps1` | `Get-WttrWeather`, `Get-WttrFormatUrl` | ~15 个 It 块 | 与 UI 层无直接关系（天气获取） |

**未覆盖直接测试的 UI 函数**: `Invoke-ConsoleMenu`、`Show-HostSelector`、`Show-SessionManager`、`New-WelcomeBanner`（纯函数有测试但集成路径无测试）〔v2.4：`Show-InputPrompt` 已删除〕、`Show-UserScoopLogo`。

---

## 2. ConsoleGuiTools 能力映射表

> **重要说明**: 以下 ConsoleGuiTools API 细节基于任务描述中给出的名称，**未经实际验证**。标注「需实测验证」的项目在实施前必须通过代码审查或实际调用确认其存在、参数和行为。

### 2.1 ConsoleGuiTools 组件列表（来自任务描述）

| 组件名 | 描述 | 适合迁移的场景 | 不适合迁移的原因 | 决策 |
|--------|------|----------------|-----------------|------|
| `Grid` / `GridRow` / `GridColumn` | 网格布局容器 | 待讨论（菜单不需要网格布局） | ShellPrompt 菜单是单列列表，Grid 适合多列数据展示 | **保留自研**: 菜单项是单列列表，Grid 提供的多列布局能力与当前交互模型不匹配 |
| `ChoiceGrid` | 选择网格 | SSH host 选择（如果需要多列展示主机列表） | 单列键盘过滤体验不如当前垂直列表 | **待确认**: 如果未来需要多列主机展示（如网格视图），可考虑迁移；否则保留当前垂直列表 |
| `Button` | 按钮控件 | 操作按钮（会话管理中的"删除确认"） | 终端场景下按钮交互需要额外按 Enter，不如键盘快捷键直接 | **保留自研**: 当前菜单用键盘快捷键（Enter 确认/Esc 退出）比点击按钮更高效；Button 适合 GUI 但不适合纯键盘交互 |
| `TextBlock` | 静态文本块 | 显示描述文本（菜单项描述、帮助文本） | 已有的 ANSI 字符串拼接足够简单 | **迁移**: 可用于替代 `New-DynamicHelpPanel` 的静态文本生成；但 ANSI 字符串拼接足够简单，ROI 不高 |
| `TextInput` | 文本输入框 | 输入提示（会话名、主机名输入） | 需要支持默认值/校验/取消/Secret 模式；ConsoleGuiTools TextInput 可能不具备完整的校验器契约 | **保留自研**: `Show-InputPrompt` 需要 Validator scriptblock（支持 bool/hashtable/throw 三种契约）、Secret 模式、Cancel 状态，当前 ConsoleGuiTools TextInput API（需实测验证）不确定是否支持这些能力〔v2.4：`Show-InputPrompt` 已删除〕 |
| `CheckBox` | 复选框 | 未来可能的批量选择场景 | 当前无此需求 | **保留**: 暂无需求 |
| `Selection` / `SelectionOption` | 选择控件 | 可能替代 `Write-MenuItem` 的渲染 | 需要验证 Selection 是否支持键盘过滤（当前核心能力） | **需实测验证**: Selection 是否支持实时键盘过滤？如果支持，可以替代 `Invoke-MenuMachine` 的渲染层 |
| `Label` | 标签控件 | 显示静态文本（徽章、状态信息） | 已有 ANSI 字符串拼接足够简单 | **迁移**: 用于替代 `Format-StatusBadge` 的字符串拼接；ROI 不高 |
| `StackPanel` | 堆叠布局 | 多行垂直排列（Footer 动态帮助） | 当前 `New-DynamicHelpPanel` 已足够简单 | **保留**: 当前实现足够简单，重构 ROI 低 |
| `Tab` / `TabControl` | 选项卡控件 | 会话管理中不同类型会话的分组 | 当前菜单没有 tab 切换需求 | **保留**: 暂无需求 |
| `ProgressBar` / `Spinner` | 进度条/旋转动画 | 替代 `Show-ProgressSpinner` 的加载动画 | 已有双轨制（Legacy + Spectre）且工作良好 | **待讨论**: 如果 ConsoleGuiTools 的 ProgressBar/Spinner 在 PS 5.1 下可用且稳定，可以作为第三轨；当前 Spectre 在 PS 7.4+ 且 Legacy 在 PS 5.1 已足够 |
| `Separator` / `WindowBorder` | 分隔符/窗口边框 | 菜单边框、区域分隔 | 已有的 ANSI 边框字符（`+--...--`）足够灵活 | **保留**: ANSI 边框在终端兼容性和自定义性上优于固定组件 |
| `AnsiConsole` / `Theme` | ANSI 控制台封装/主题 | 主题系统（颜色、样式） | 主题能力已被 `Initialize-Config.ps1` 的 Colors 域 + `Get-CachedConfig` 覆盖 | **保留自研**: 已有完善的主题配置系统，不需引入额外的主题抽象；且 ConsoleGuiTools Theme 与当前 PS 5.1 兼容性不确定 |
| `ReadKey` / `ReadLine` | 键盘读取 | 替代 `Invoke-MenuMachine` 的键盘读取层 | 当前 CSI 三字节序列重组逻辑复杂 | **需实测验证**: ConsoleGuiTools 的 ReadKey 是否处理了 Windows Terminal + PS 5.1 下方向键被拆为 3 字节的问题？如果已处理，可以简化 `ConvertTo-CsiArrowKey`〔v2.4：`ConvertTo-CsiArrowKey` 已删除〕 |

### 2.2 映射决策汇总

| ConsoleGuiTools 组件 | 映射决策 | 数量 |
|---------------------|----------|------|
| **可迁移** | `TextBlock`（描述文本）、`Label`（徽章文本） | 2 条 |
| **保留自研** | `Grid`（单列菜单不需要）、`Button`（键盘交互比点击高效）、`TextInput`（校验器契约不匹配）、`CheckBox`（无需求）、`StackPanel`（已有简单实现）、`Tab/TabControl`（无需求）、`ProgressBar/Spinner`（已有双轨制）、`Separator/WindowBorder`（ANSI 边框更灵活）、`AnsiConsole/Theme`（已有主题系统） | 9 条 |
| **需实测验证** | `ChoiceGrid`（多列主机展示）、`Selection/SelectionOption`（键盘过滤支持度）、`ReadKey`（CSI 序列处理） | 3 条 |
| **待确认** | `ProgressBar/Spinner` 是否作为第三轨 | 1 条 |

---

## 3. 架构设计

### 3.1 分层建议

```
┌─────────────────────────────────────────────────────────────┐
│  业务界面层 (Business UI Layer)                            │
│  - Show-HostSelector     (SSH 主机选择)                   │
│  - Show-SessionManager    (tmux 会话管理)                  │
│  - Show-InputPrompt      (输入提示，含校验) ← v2.4 已删除     │
│  - Show-UserScoopLogo    (欢迎横幅，Public)               │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ │
│  调用方: Start-TmuxSession / Microsoft.PowerShell_profile  │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│  组件层 (Component Layer) — 新增 ShellPrompt/UI/           │
│  - GridMenu.ps1         (通用网格菜单组件)     [迁移?待验证] │
│  - StatusBadge.ps1      (状态徽章, 替代 New-StatusBadge)  │
│  - DynamicHelp.ps1      (动态帮助面板, 替代 New-DynamicHelpPanel) │
│  - ProgressIndicator.ps1 (进度指示器, 整合 spinner)        │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ │
│  这些组件可直接被业务界面层调用，也保留对下层的委托          │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│  UI 基础层 (UI Foundation Layer) — 新增 ShellPrompt/UI/    │
│  - AnsiWriter.ps1     (ANSI 写入封装: Write-AnsiLine 重构) │
│  - AnsiTheme.ps1      (主题配置: 整合 Initialize-Config 的 Colors 域) │
│  - KeyboardReader.ps1  (键盘读取: 整合 Invoke-MenuMachine 的 CSI 重组) │
│  - Layout.ps1          (布局: 重构 New-AnsiLayout 为更小函数) │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ │
│  所有 I/O 抽象在此层，之上两层完全无直接 [Console]::Write   │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│  底层依赖                                                  │
│  - Initialize-Config.ps1  (配置源: Colors/Keys/Paths/SSH)  │
│  - PwshSpectreConsole     (可选, PS 7.4+ 的 Progress 渲染) │
│  - .NET [Console] API     (底层终端 I/O)                   │
└─────────────────────────────────────────────────────────────┘
```

**新增文件清单**:

| 新增文件 | 放置位置 | 理由 |
|----------|----------|------|
| `ShellPrompt/UI/AnsiWriter.ps1` | Private/UI/ | 将 `[Console]::Write` + ANSI 转义封装为可测试的函数；作为 I/O 抽象层，所有上层不直接调用 `[Console]` |
| `ShellPrompt/UI/AnsiTheme.ps1` | Private/UI/ | 将 `Initialize-Config.ps1` 的 Colors 域独立为主题访问器；支持主题切换（不能放在已有 Initialize-Config.ps1 中，因为那是单例配置） |
| `ShellPrompt/UI/KeyboardReader.ps1` | Private/UI/ | 将 CSI 三字节序列重组封装为独立函数；提供 `Read-Key` / `Read-KeyWithCSI` 接口，供组件层使用 |
| `ShellPrompt/UI/Layout.ps1` | Private/UI/ | 将 `New-AnsiLayout` 拆分为更小的纯函数：`New-LayoutBox`、`Set-LayoutOrigin`、`Format-LayoutLine`；支持组件层组合布局 |
| `ShellPrompt/UI/GridMenu.ps1` | Private/UI/ | 可选迁移目标：封装 `ChoiceGrid` / `Selection` 交互；如果 ConsoleGuiTools Selection 不支持键盘过滤，保留当前 `Invoke-MenuMachine` 路径 |
| `ShellPrompt/UI/StatusBadge.ps1` | Private/UI/ | 将 `New-StatusBadge` + `Format-StatusBadge` 合并为更小的组件；支持更多状态类型扩展 |
| `ShellPrompt/UI/DynamicHelp.ps1` | Private/UI/ | 将 `New-DynamicHelpPanel` + `Get-SessionActionHelp` 合并；支持更多动作类型配置化 |
| `ShellPrompt/UI/ProgressIndicator.ps1` | Private/UI/ | 整合 `Show-ProgressSpinner` + `Invoke-WithProgress` 为统一进度指示器；支持 Legacy/Spectre/ConsoleGuiTools 三轨制 |

**文件重命名/移动**（保持 Public API 不变）:

| 操作 | 原路径 | 新路径 | 理由 |
|------|--------|--------|------|
| 移动 | `Private/Invoke-MenuMachine.ps1` | `Private/UI/MenuMachine.ps1` | UI 层内部组织调整 |
| 移动 | `Private/Write-MenuItem.ps1` | `Private/UI/MenuItem.ps1` | UI 层内部组织调整 |
| 移动 | `Private/New-AnsiLayout.ps1` | `Private/UI/LayoutBuilder.ps1` | 与新的 `Layout.ps1` 区分 |

### 3.2 主题/配置设计

**与 Initialize-Config.ps1 的衔接**:

```
用户配置 ($HOME/.ShellPrompt/config.ps1)
    │  (覆盖默认配置)
    ▼
Initialize-Config.ps1 ($script:Config)
    │  (Colors/Keys/Paths/SSH 四域)
    ▼
AnsiTheme.ps1 ($script:UITheme)
    │  (UI 专用主题键)
    ▼
组件层调用 Get-UITheme / Get-UIColor
```

**新增主题键设计**（在 `Initialize-Config.ps1` 中扩展 Colors 域）:

```powershell
# 在 Initialize-Config.ps1 的 Colors 域中新增
$script:Config.Colors = [ordered]@{
    # ... 现有键 ...
    
    # === UI 层新增键（需用户确认）===
    Blue    = "$Esc[38;2;100;180;255m"   # Attached 状态色；当前硬编码
    Yellow  = "$Esc[38;2;230;180;80m"   # Warning/Pending 状态色；当前硬编码
    Red     = "$Esc[38;2;220;100;100m"  # NetworkError 状态色；当前硬编码
    
    # 主题偏好键（需新增）
    ThemeName        = 'default'          # 主题名: 'default' / 'minimal' / 'high-contrast'
    UseUnicodeGlyphs = $true              # 是否使用 Unicode 符号（如 ●/○/✗）；false 则降级到 ASCII
    EnableSpectre    = 'auto'             # 'auto' / 'always' / 'never'；auto 时按 PS 版本自动选择
    MenuAnimation    = $true               # 是否启用菜单动画（如选中项高亮过渡）
}

# AnsiTheme.ps1 读取 Colors 域，映射到组件需要的语义键
function Get-UIColor {
    param([ValidateSet('Primary', 'Accent', 'Muted', 'Border', 'Danger', 'Warning', 'Info', 'Online', 'Attached', 'Detached')]$Role)
    # 内部映射 Colors 域键到语义角色
    # 允许用户通过 Colors.Blue / Colors.Yellow 覆盖
}
```

**关键约束**:

- **不得硬编码用户偏好**：所有颜色/符号/动画偏好必须通过配置键访问
- **配置优先级**：`User config ($HOME/.ShellPrompt/config.ps1)` → `Default config (Initialize-Config.ps1)` → `Built-in fallback`
- **主题键**：`ThemeName` / `UseUnicodeGlyphs` / `EnableSpectre` / `MenuAnimation` 四个新键需要用户确认是否加入配置

### 3.3 降级策略

```
┌──────────────────────────────────────────────────────────────┐
│  入口: Test-ConsoleGuiToolsAvailable                         │
│  (探测 ConsoleGuiTools 模块是否可用)                        │
└──────────────────────────────────────────────────────────────┘
                            │
        ┌───────────────────┼───────────────────┐
        ▼                   ▼                   ▼
   [ConsoleGuiTools    [PwshSpectreConsole   [Legacy ANSI
    可用且 PS 7.4+]     可用且 PS 7.4+]       转义]
        │                   │                   │
        ▼                   ▼                   ▼
   路径 C (新)        路径 S (已有)        路径 L (已有)
```

| 环境 | 路径 | 触发条件 | 渲染能力 |
|------|------|----------|----------|
| **ConsoleGuiTools 可用 + PS 7.4+** | C (新路径) | `Test-ConsoleGuiToolsAvailable` 返回 `$true` | `ChoiceGrid` / `Selection` / `ProgressBar` / `Spinner` / `TextInput` |
| **PwshSpectreConsole 可用 + PS 7.4+** | S (已有) | `Test-SpectreSpinnerAvailable` 返回 `$true` | `Invoke-SpectreCommandWithStatus` / `Write-SpectreHost` |
| **PS 5.1 / 模块缺失 / 强制 legacy** | L (已有) | `Test-SpectreSpinnerAvailable` 返回 `$false` | `[Console]::Write` + ANSI 转义序列 |

**各层降级细节**:

| 层级 | 降级场景 | 降级行为 |
|------|----------|----------|
| **ConsoleGuiTools (路径 C)** | 模块不可用 / PS < 7.4 | 回退到路径 S (Spectre) 或 L (Legacy) |
| **键盘读取** | 非交互式终端 / 重定向 | 降级到 `Read-Host`（丢失键盘快捷键体验） |
| **ANSI 渲染** | 非 ANSI 终端（`$env:TERM` 不含 `color`） | 降级到纯 ASCII 输出（`UseUnicodeGlyphs=$false` 自动生效） |
| **Windows 控制台宿主 (conhost.exe)** | conhost 不支持某些 ANSI 转义 | 通过 `$Host.UI.RawUI.BufferSize` 检测，如果不支持 ANSI 则回退 |
| **Windows Terminal** | 基本全支持 | 使用完整 ANSI 能力 |
| **VSCode 集成终端** | 某些 ANSI CSI 序列支持不完整 | 使用较保守的 ANSI 子集 |

### 3.4 兼容性约束

> 以下约束**不得在重构中破坏**，否则属于 breaking change。

| 约束 | 当前实现位置 | 重构后要求 |
|------|-------------|-----------|
| **tmux 会话删除必须显式用户确认** | `Show-SessionManager` 中"删除"项的 `Severity=Danger` + 菜单内无法直接删除（需进入二级菜单） | 保留现有的交互流程：选中"删除" → Enter → 二次确认提示 |
| **SSH 终端状态保存/重置的 try/finally 模式** | `Save-OriginalTerminalState` + `Reset-TerminalMode` 在 `Connect-TmuxSession` / `Start-TmuxSession` 等函数中使用〔v2.4：`Start-SshInteractive` 已删除〕 | 不得移除或改变调用模式 |
| **Public 命令签名不变** | `Show-UserScoopLogo`、`Start-TmuxSession`、`Copy-SshPublicKey`、`Invoke-Reload` | 这些是导出 API，参数集和返回值类型不得改变 |
| **Private 函数不暴露** | `PrivateData.PSData` 中 `FunctionsToExport` 只包含 5 个 Public 命令 | 新的 UI 组件函数不得出现在 `FunctionsToExport` 中 |
| **现有 Pester 测试通过** | `ShellPrompt.Tests.ps1` / `Show-ProgressSpinner.Tests.ps1` / `Get-WttrWeather.Tests.ps1` | 重构后所有现有测试必须继续通过 |
| **PS 5.1 兼容** | `Initialize-Config.ps1` 中用 `[char]27` 替代 `` `e`` | 所有新增代码必须兼容 PS 5.1 |

---

## 4. 实施批次划分

### 批次 1: 菜单与会话管理

**目标**: 将 `Show-HostSelector` / `Show-SessionManager` 的渲染层迁移到新 UI 基础层

**涉及文件**:

| 文件 | 操作 |
|------|------|
| `Private/UI/KeyboardReader.ps1` | **新增**: 封装 CSI 三字节序列重组 |
| `Private/UI/Layout.ps1` | **新增**: 布局纯函数 |
| `Private/UI/MenuMachine.ps1` | **移动**: 原 `Invoke-MenuMachine.ps1` |
| `Private/UI/MenuItem.ps1` | **移动**: 原 `Write-MenuItem.ps1`（保留 `New-MenuItem`） |
| `Private/Show-HostSelector.ps1` | **重构**: 调用方不变，内部委托新的 UI 层 |
| `Private/Show-SessionManager.ps1` | **重构**: 调用方不变，内部委托新的 UI 层 |
| `Private/New-DynamicHelpPanel.ps1` | **移动到** `Private/UI/DynamicHelp.ps1` |
| `Private/New-StatusBadge.ps1` | **移动到** `Private/UI/StatusBadge.ps1` |

**前置依赖**:

- 新增文件需在 `ShellPrompt.psm1` 中 dot-source（按字母顺序）
- `Invoke-MenuMachine` 移动路径后内部 dot-source 路径需更新

**验收标准**:

```powershell
# 1. 模块加载正常
Import-Module ./ShellPrompt -Force

# 2. Pester 测试全部通过
Invoke-Pester ./ShellPrompt/Tests/ -Output Detailed

# 3. PSScriptAnalyzer 无 Error
Invoke-ScriptAnalyzer ./ShellPrompt -Settings ./ShellPrompt/Settings.ScriptAnalyzer.psd1 -Severity Error

# 4. 手动验证: 启动 pwsh，调用 sss，确认主机选择菜单和会话管理菜单渲染正常
```

**风险与回滚**:

| 风险 | 概率 | 影响 | 缓解措施 |
|------|------|------|----------|
| CSI 序列重组逻辑在移动后行为改变 | 中 | 高 | 复用现有 `Send-MenuKey` / `ConvertTo-CsiArrowKey` 测试，覆盖相同 case〔v2.4：`ConvertTo-CsiArrowKey` 已删除〕 |
| 路径移动后 dot-source 顺序错误 | 高 | 高 | 在 `ShellPrompt.psm1` 中验证加载顺序；先临时 alias 旧路径到新路径 |
| PS 5.1 ConsoleKeyInfo 跨 scope 字段丢失问题在移动后加剧 | 低 | 高 | 使用现有的 `& $mod {}` 闭包调用模式，不改变测试调用方式 |

**回滚方式**: `git checkout -- ShellPrompt/Private/Invoke-MenuMachine.ps1 ShellPrompt/Private/Write-MenuItem.ps1`

---

### 批次 2: 欢迎横幅与状态栏

**目标**: 将 `Show-UserScoopLogo` / `New-WelcomeBanner` / `New-StatusBadge` 的渲染层抽象化，支持主题切换

**涉及文件**:

| 文件 | 操作 |
|------|------|
| `Private/UI/AnsiWriter.ps1` | **新增**: ANSI 写入封装（替代直接 `[Console]::Write` 调用） |
| `Private/UI/AnsiTheme.ps1` | **新增**: 主题配置访问器（Colors → UI 语义角色映射） |
| `Private/UI/StatusBadge.ps1` | **移动+重构**: 原 `New-StatusBadge.ps1`，集成到 UI 层 |
| `Private/New-WelcomeBanner.ps1` | **重构**: 内部使用 `AnsiWriter` 替代直接字符串拼接 |
| `Public/Show-UserScoopLogo.ps1` | **重构**: 内部使用 `AnsiWriter` 输出banner；**不改变 Public 签名** |
| `ShellPrompt/Private/Initialize-Config.ps1` | **扩展**: 新增 Colors 域键（Blue/Yellow/Red/ThemeName/UseUnicodeGlyphs） |

**前置依赖**:

- 批次 1 完成（UI 基础层已建立）
- `AnsiTheme.ps1` 需在 `Initialize-Config.ps1` 之后加载（读取 `$script:Config`）

**验收标准**:

```powershell
# 1. 启动新的 PowerShell，确认欢迎 banner 正常显示
# （banner 在 profile 阶段输出，需手动验证）

# 2. 模块加载正常
Import-Module ./ShellPrompt -Force

# 3. Pester 测试通过
Invoke-Pester ./ShellPrompt/Tests/ -Output Detailed

# 4. PSScriptAnalyzer 无 Error
Invoke-ScriptAnalyzer ./ShellPrompt -Settings ./ShellPrompt/Settings.ScriptAnalyzer.psd1 -Severity Error

# 5. 主题切换验证（需手动）:
#    在 ~/.ShellPrompt/config.ps1 中设置 $Config.Colors.UseUnicodeGlyphs = $false
#    重新加载，确认状态徽章从 ● 降级到 ASCII 字符
```

**风险与回滚**:

| 风险 | 概率 | 影响 | 缓解措施 |
|------|------|------|----------|
| `Write-Host` 在 profile 阶段的执行顺序依赖 dot-source 顺序 | 中 | 中 | 保持 `Microsoft.PowerShell_profile.ps1` 中 Phase 1 的 dot-source 顺序不变 |
| `Show-UserScoopLogo` 的固定宽度 49 与 `New-WelcomeBanner` 默认 Width=60 不一致 | 低 | 低 | 统一为 Width=49（当前 profile 调用使用的值） |
| Colors 域新增键后用户配置覆盖逻辑是否正确 | 中 | 中 | 测试 `Get-CachedConfig` 对新键的 fallback 行为 |

**回滚方式**: `git checkout -- ShellPrompt/Private/New-WelcomeBanner.ps1 ShellPrompt/Public/Show-UserScoopLogo.ps1`

---

### 批次 3: 进度与输入交互

**目标**: 整合 `Show-ProgressSpinner` / `Invoke-WithProgress` / `Show-InputPrompt` 为统一的进度指示器和输入组件〔v2.4：`Show-InputPrompt` 已删除〕；引入 ConsoleGuiTools 作为第三轨（**可选，需实测验证**）

**涉及文件**:

| 文件 | 操作 |
|------|------|
| `Private/UI/ProgressIndicator.ps1` | **新增**: 整合 spinner + progress + 状态封装 |
| `Private/UI/InputPrompt.ps1` | **重构**: 整合 `Show-InputPrompt.ps1` 的纯函数（Update-InputBuffer / Test-InputValidation）到 UI 层〔v2.4：`Show-InputPrompt.ps1` 已删除，其纯函数随之内联移除〕 |
| `Private/Show-ProgressSpinner.ps1` | **移动到** `Private/UI/ProgressIndicator.ps1` |
| `Private/Invoke-WithProgress.ps1` | **移动到** `Private/UI/ProgressIndicator.ps1`（保留 Public API 兼容） |
| `Private/Show-InputPrompt.ps1` | **移动到** `Private/UI/InputPrompt.ps1` |〔v2.4：该文件已删除，未移动〕
| `ShellPrompt/ShellPrompt.psm1` | **更新**: dot-source 新路径 |

**前置依赖**:

- 批次 1 + 批次 2 完成
- ConsoleGuiTools 可用性探测函数 `Test-ConsoleGuiToolsAvailable` 需新增

**验收标准**:

```powershell
# 1. 模块加载正常
Import-Module ./ShellPrompt -Force

# 2. Pester 测试通过（Invoke-WithProgress 相关测试）
Invoke-Pester ./ShellPrompt/Tests/ -Output Detailed

# 3. 手动验证:
#    pwsh -Command "Import-Module ./ShellPrompt; Start-TmuxSession -HostName test"
#    确认 SSH 探测期间 spinner 动画正常显示
#    确认超时行为正常（如果有）

# 4. PSScriptAnalyzer 无 Error
Invoke-ScriptAnalyzer ./ShellPrompt -Settings ./ShellPrompt/Settings.ScriptAnalyzer.psd1 -Severity Error
```

**风险与回滚**:

| 风险 | 概率 | 影响 | 缓解措施 |
|------|------|------|----------|
| `Invoke-WithProgress` 的 Spectre 路径不支持硬超时（已有文档说明） | 中 | 中 | 保持 `-ForceLegacy` 选项可用；路由逻辑不变〔v2.0：`-ForceLegacy` 已移除〕 |
| ConsoleGuiTools Progress/Spinner 在 PS 5.1 下的行为（需实测） | 高 | 中 | 如果 ConsoleGuiTools 不支持 PS 5.1，保持 Legacy 路径作为唯一 fallback |
| `Show-InputPrompt` 的 Secret 模式在降级到 `Read-Host` 后失效 |〔v2.4：`Show-InputPrompt` 已删除〕 低 | 低 | 当前行为如此，不是新引入的问题 |

**回滚方式**: `git checkout -- ShellPrompt/Private/Show-ProgressSpinner.ps1 ShellPrompt/Private/Invoke-WithProgress.ps1 ShellPrompt/Private/Show-InputPrompt.ps1`〔历史文案；其中 `Show-InputPrompt.ps1` 已于 v2.4 删除〕

---

## 5. 风险清单

### 风险 1: Spectre.Console 2.6.3 在 PS 5.1 下的行为

**描述**: `PwshSpectreConsole.psd1` 声明 `PowerShellVersion = '7.4'`，PS 5.1 加载会直接失败。当前通过 `try/catch + Write-Verbose` 静默忽略，但这意味着用户在 PS 5.1 下永远不知道 Spectre 不可用。

**影响**: 重构中如果引入新的 Spectre 依赖，PS 5.1 用户不会收到任何提示。

**缓解措施**:

- 保持现有的 `Test-SpectreSpinnerAvailable` 探测逻辑
- 在 `Initialize-Config.ps1` 加载完成后，如果检测到 PS 5.1 + Spectre 不可用，写入一次 `Write-Verbose` 提示用户（不同于当前的静默忽略）
- 重构文档中明确说明 PS 5.1 的能力上限

**概率**: 已知（模块已设计为 PS 5.1 兼容）

**影响**: 中（PS 5.1 用户已有 fallback）

---

### 风险 2: ConsoleGuiTools 独占控制台导致的按键捕获冲突

**描述**: ConsoleGuiTools 的 `Selection` / `ChoiceGrid` 等组件在渲染时会接管控制台的键盘事件。如果 ShellPrompt 的 `Invoke-MenuMachine` 也同时读取键盘，会产生冲突（按键被两个组件同时消费）。

**影响**: 如果 ConsoleGuiTools 组件不支持自定义键盘过滤（当前 `Show-HostSelector` 的核心能力），迁移后实时过滤功能可能丢失。

**缓解措施**:

- **实施前**必须实测验证 ConsoleGuiTools Selection 是否支持键盘过滤
- 如果不支持，保留 `Invoke-MenuMachine` 作为菜单渲染层，ConsoleGuiTools 仅用于进度条等被动组件
- 如果支持，评估是否可以在 ConsoleGuiTools 内部实现键盘过滤（而非外部状态机）

**概率**: 高（ConsoleGuiTools API 能力未知）

**影响**: 高（核心交互功能可能丢失）

---

### 风险 3: RawUI 光标控制与 Windows Terminal 兼容性

**描述**: 当前 UI 层大量使用 `[Console]::Write` + ANSI CSI 序列 (`\e[Line;H`)，这依赖于终端对 ANSI CSI 的支持。Windows Terminal 支持良好，但 conhost.exe（传统 Windows 控制台宿主）支持不完整。

**影响**: 在 conhost 环境下，布局可能错位、颜色可能失效。

**缓解措施**:

- 保持现有的 `$Host.UI.RawUI.BufferSize` / `WindowSize` 检测逻辑
- 引入 `$env:WT_SESSION` 检测（Windows Terminal 会在环境变量中设置此变量）
- 如果检测到非 Windows Terminal 且非 ANSI 兼容终端，回退到 Legacy 纯 ASCII 输出

**概率**: 中（大多数现代 Windows 用户使用 Windows Terminal）

**影响**: 中（老用户可能遇到布局问题）

---

### 风险 4: 现有 Pester 测试脆弱性

**描述**: 当前测试大量使用 `& $mod {}` 闭包调用模式来避免 PSObject 跨边界字段丢失问题。如果重构中改变了函数作用域或加载顺序，这些测试可能失败。

**影响**: 重构后测试不通过，但功能可能正常。

**缓解措施**:

- 在每个批次重构前，运行现有测试套件作为基线
- 重构中保持 `Private/` 函数的 dot-source 顺序与当前一致
- 测试调用方式（`& $mod {}`）保持不变
- 如果测试失败，优先修复测试而非回退功能

**概率**: 高（重构必然涉及文件移动）

**影响**: 中（测试修复成本可控）

---

### 风险 5: README 需要同步的章节

**描述**: 重构会引入新的 UI 组件、新的配置键、新的依赖关系。当前 README 中的以下章节需要同步更新：

| 章节 | 需要更新的内容 |
|------|----------------|
| 交互式 UI 组件 (P2 阶段) | 新增 UI 层架构说明；进度指示器从"双轨制"改为"三轨制" |
| 配置 / 完整配置项 | 新增 Colors 域键（Blue/Yellow/Red/ThemeName/UseUnicodeGlyphs/EnableSpectre/MenuAnimation） |
| 命令一览 | `Invoke-WithProgress` 的说明需要更新（新增 ConsoleGuiTools 路径） |
| 架构 / 目录结构 | 新增 `ShellPrompt/UI/` 目录及其子文件说明 |
| 故障排除 | 新增 ConsoleGuiTools 不可用时的诊断步骤 |

**影响**: 用户文档与实际功能不一致，可能导致用户困惑。

**缓解措施**:

- 在每个批次完成后立即更新 README 对应章节
- 更新前先阅读当前 README 内容，确保不覆盖未涉及的部分
- 将 README 更新作为批次验收标准的一部分

**概率**: 确定（重构必然需要文档更新）

**影响**: 低（不影响功能，只影响用户体验）

---

## 6. 待用户确认的开放问题

> 以下 5 条开放问题需要在实施前得到用户的明确答复。

### 问题 1: ConsoleGuiTools 角色定位

**问题描述**: ConsoleGuiTools 的 `Selection` / `ChoiceGrid` / `TextInput` 是否应该作为 ShellPrompt UI 层重构的主要目标？当前分析表明，这些组件的能力（键盘过滤支持度、校验器契约）与现有 `Invoke-MenuMachine` 存在能力差距〔v2.4：`Show-InputPrompt` 已删除〕。

**候选方案**:

| 方案 | 描述 | 推荐 |
|------|------|------|
| A | **不做 ConsoleGuiTools 迁移**：只将现有 UI 函数重构到 `Private/UI/` 子目录下，保持双轨制（Legacy + Spectre）不变 | **推荐** |
| B | **选择性迁移**：ConsoleGuiTools 只用于 `ProgressBar/Spinner`（第三轨），菜单和输入保留自研 | 次推荐 |
| C | **全面迁移**：将 `Show-HostSelector` / `Show-SessionManager` 迁移到 ConsoleGuiTools，同时重构键盘过滤逻辑 | 高风险 |

**推荐**: 方案 A。理由：ConsoleGuiTools API 能力未经验证，全面迁移风险高；现有双轨制已覆盖 PS 5.1 (Legacy) 和 PS 7.4+ (Spectre)。

---

### 问题 2: 新增主题配置键的采纳

**问题描述**: 为了支持主题化和 Unicode/ASCII 降级，需要在 `Initialize-Config.ps1` 中新增 4 个配置键。是否采纳？

**候选方案**:

| 方案 | 描述 | 推荐 |
|------|------|------|
| A | **全部采纳**：新增 `ThemeName` / `UseUnicodeGlyphs` / `EnableSpectre` / `MenuAnimation` 四个键 | **推荐** |
| B | **部分采纳**：只采纳 `UseUnicodeGlyphs`（最影响显示），其他维持现状 | 次推荐 |
| C | **不采纳**：维持当前硬编码的颜色/符号 | 不推荐（违反"不得硬编码用户偏好"原则） |

**推荐**: 方案 A。理由：`ThemeName` / `EnableSpectre` 是配置优先级的体现；`UseUnicodeGlyphs` 对非 Unicode 终端用户必要；`MenuAnimation` 可保留默认值 `$true`。

---

### 问题 3: 进度指示器是否引入第三轨（ConsoleGuiTools）

**问题描述**: 如果采纳问题 1 的方案 B，进度指示器（spinner/progress）是否要引入 ConsoleGuiTools 作为第三轨？

**候选方案**:

| 方案 | 描述 | 推荐 |
|------|------|------|
| A | **不引入第三轨**：保持当前双轨制（Legacy + Spectre），ConsoleGuiTools 不用于进度指示器 | **推荐** |
| B | **引入第三轨**：如果 ConsoleGuiTools ProgressBar/Spinner 在 PS 5.1 下可用且 API 稳定，作为第三轨 | 次推荐（需实测） |

**推荐**: 方案 A。理由：当前 Spectre 在 PS 7.4+ 已提供良好的进度动画；Legacy 在 PS 5.1 下工作正常；引入第三轨增加维护复杂度。

---

### 问题 4: PS 5.1 下 Spectre 不可用时的提示策略

**问题描述**: 当前 PS 5.1 下 Spectre 不可用时，模块静默忽略（只 `Write-Verbose`）。是否改为显式提示用户？

**候选方案**:

| 方案 | 描述 | 推荐 |
|------|------|------|
| A | **保持静默**：当前行为，用户不需要知道内部使用了哪个渲染路径 | **推荐** |
| B | **首次加载时提示**：在 PS 5.1 下首次加载模块时，写入一次 `Write-Warning` 提示"Spectre 不可用，使用兼容模式" | 次推荐 |
| C | **始终提示**：每次使用 Spectre 相关功能时提示 | 不推荐（噪音大） |

**推荐**: 方案 A。理由：大多数用户不需要知道内部渲染路径差异；Verbose 输出可通过 `$VerbosePreference` 控制。

---

### 问题 5: ShellPrompt/UI/ 子目录的采纳

**问题描述**: 重构中计划新增 `ShellPrompt/UI/` 子目录来组织 UI 层组件。这将改变现有 `Private/` 扁平的目录结构。

**候选方案**:

| 方案 | 描述 | 推荐 |
|------|------|------|
| A | **采纳 `UI/` 子目录**：将所有 UI 相关函数移动到 `ShellPrompt/UI/`，`Private/` 只保留非 UI 辅助函数 | **推荐** |
| B | **保留扁平结构**：所有函数仍在 `Private/` 下，通过文件名前缀组织（如 `UI-AnsiWriter.ps1`） | 次推荐 |
| C | **不重构目录结构**：只重构代码内容，不改变文件位置 | 不推荐（目录结构重组是架构清晰化的基础） |

**推荐**: 方案 A。理由：`UI/` 子目录明确区分了 UI 组件层和业务逻辑层；与 `Public/` / `Private/` 的分离一致。

---

## 附录 A: 文件变更摘要

### A.1 当前文件 → 重构后文件映射

| 当前路径 | 重构后路径 | 操作 |
|----------|------------|------|
| `Private/Invoke-MenuMachine.ps1` | `Private/UI/MenuMachine.ps1` | 移动 |
| `Private/Write-MenuItem.ps1` | `Private/UI/MenuItem.ps1` | 移动 |
| `Private/New-StatusBadge.ps1` | `Private/UI/StatusBadge.ps1` | 移动 |
| `Private/New-DynamicHelpPanel.ps1` | `Private/UI/DynamicHelp.ps1` | 移动 |
| `Private/Show-ProgressSpinner.ps1` | `Private/UI/ProgressIndicator.ps1` | 移动 |
| `Private/Invoke-WithProgress.ps1` | `Private/UI/ProgressIndicator.ps1` | 合并 |
| `Private/Show-InputPrompt.ps1` | `Private/UI/InputPrompt.ps1` | 移动 |〔v2.4：该文件已删除，未移动〕
| `Private/New-WelcomeBanner.ps1` | （保持不动，内容重构） | 重构 |
| `Private/New-AnsiLayout.ps1` | `Private/UI/LayoutBuilder.ps1` | 移动+重构 |

### A.2 新增文件清单

| 新增路径 | 说明 |
|----------|------|
| `Private/UI/AnsiWriter.ps1` | ANSI 写入封装 |
| `Private/UI/AnsiTheme.ps1` | 主题配置访问器 |
| `Private/UI/KeyboardReader.ps1` | 键盘读取 + CSI 重组 |
| `Private/UI/Layout.ps1` | 布局纯函数 |
| `Private/UI/GridMenu.ps1` | 可选：ConsoleGuiTools 菜单封装（需实测验证） |

### A.3 保持不变的文件（Public API）

| 文件 | 原因 |
|------|------|
| `Public/Show-UserScoopLogo.ps1` | Public API，签名不变 |
| `Public/Start-TmuxSession.ps1` | Public API，签名不变 |
| `Public/Copy-SshPublicKey.ps1` | Public API，签名不变 |
| `Public/Invoke-Reload.ps1` | Public API，签名不变 |
| `ShellPrompt.psd1` | 模块清单，FunctionsToExport 不变 |
| `ShellPrompt.psm1` | 入口脚本，dot-source 路径需更新 |

---

## 附录 B: 测试覆盖补充建议

> 以下测试在当前测试套件中缺失，建议在对应批次完成后添加。

| 测试场景 | 覆盖函数 | 说明 |
|----------|----------|------|
| `New-AnsiLayout` 居中模式 | `New-AnsiLayout` | 验证 `-Center` 模式下 `OriginX` / `OriginY` 计算正确 |
| `KeyboardReader` CSI 重组 | `ConvertTo-CsiArrowKey` | 添加非法 CSI 序列（ESC [ 0 X）的处理测试 |〔v2.4：`ConvertTo-CsiArrowKey` 已删除，CSI 重组由主循环状态机承担〕
| `AnsiWriter` 非 ANSI 终端降级 | `Write-AnsiLine` | 验证检测到非 ANSI 终端时的降级行为 |
| `AnsiTheme` 主题切换 | `Get-UIColor` | 验证切换 `ThemeName` 后颜色映射正确变化 |
| `ProgressIndicator` 三轨制路由 | `Invoke-WithProgress` | 添加 ConsoleGuiTools 可用时的路由测试（Mock） |
| `Show-InputPrompt` Secret 模式 | `Show-InputPrompt` | 验证 Secret 模式下输入显示为 `*` |〔v2.4：`Show-InputPrompt` 已删除〕

---

## 附录 C: 实施结果归档

> 本节记录三轮实测选型的最终结论与实际落地内容，是本文档的**权威部分**。

### C.1 三轮实测选型结论

| 轮次 | 调研对象 | 结论 |
|------|---------|------|
| 1 | `Microsoft.PowerShell.ConsoleGuiTools` | 归档停更，微软官方不再维护；命令名被社区以 `PSTui` 续作。**淘汰** |
| 2 | `ConsoleMonster` / `PoshTui` / `PsUi` | 或体积臃肿、或 API 不对口、或与 Terminal.Gui 版本争用。**全部淘汰并从 `Modules/` 删除** |
| 3 | `PSTui 1.0.5` | Terminal.Gui v2 + .NET 10，PS 7.6+；`Out-ConsoleGridView` 表格视图能力对口。**选为主轨** |

### C.2 实测确认的 PSTui 事实（与选型假设的差异）

| 项 | 选型时的假设 | 实测结果 |
|---|---|---|
| `Out-ConsoleGridView` 的 `Debug` 参数 | 存在 | **不存在**。未向其传 `-Debug` |
| `OutputModeOption` 枚举 | 未知 | `None=0` / `Single=1` / `Multiple=2` |
| `FocusTarget` 枚举 | 未知 | `Table=0` / `Filter=1` |
| `Get-Command` 是否触发模块自动加载 | 认为不触发 | **会触发**。因此检测函数改用 `-ListAvailable` / `-ListAvailable -All` |
| 公开 Models 类型是否暴露 Color/Theme/Style | 假设有 | **没有**。行级配色不可配置 → 改用 `State` 列 + 符号 |
| 非交互宿主行为 | 未知 | 输入重定向下抛可捕获的 `PSNotSupportedException`（`Not supported in this environment (when input is redirected).`）并返回 `$null`，**不会卡死** |
| `Terminal.Gui.dll` 版本争用 | 担心多模块各带一份 | `Modules/PSTui/1.0.5/Terminal.Gui.dll 2.4.10.0`，无争用。`PwshSpectreConsole` 依赖的是 Spectre.Console，**不绑定 Terminal.Gui，不算冲突** |

### C.3 最终架构：单轨菜单（2026-10-18 起）

> **历史说明**: 本节最初设计的是「PSTui 主轨 + AnsiFallback 降级轨」双轨结构。自 2026-10-18 起，AnsiFallback 降级轨已**整体移除**，控制台 UI 改为**单轨 GridView**。以下为单轨结构的最终形态。

```
ShellPrompt.psm1 (加载期)
  └─ Get-ConsoleUiBackend  ──►  $script:ConsoleUiBackend = { Backend='GridView'; Available; Reason; Conflicts; PstuiVersion; TerminalGuiVersion }
        │ 主轨不可用 → Write-Warning（加载期不 throw）
        ▼
Show-HostSelector / Show-SessionManager / Show-TmuxSessionList   ← 纯分发器，不使用 @PSBoundParameters
   └─ Assert-ConsoleUiReady -Feature <功能名>   ← 主轨不可用时抛可定位的终止错误
        ▼
      GridView → Invoke-GridViewHostSelector / Invoke-GridViewSessionManager / Invoke-GridViewSessionList
                   (Private/Invoke-GridViewMenu.ps1, 基于 Out-ConsoleGridView)
```

- 检测维度（全部满足才算主轨可用）：PS ≥ 7.6 / `PSTui` 可发现 / `Out-ConsoleGridView` 唯一来源为 PSTui / 无历史冲突模块 / 已加载的 `Terminal.Gui` 主版本为 2 / stdin 未重定向。
- 冲突模块名单：`Microsoft.PowerShell.ConsoleGuiTools`、`ConsoleMonster`、`PoshTui`、`PsUi`。
- **不再有 `UI.Backend` 配置项**，也不再有 `-Backend` 参数；旧配置中的 `UI.Backend = 'AnsiFallback'` 被忽略。
- 命名遵循 AGENTS.md 动词-名词规范，因此**没有** `Show-HostSelector-PSTui` 这类连字符后缀函数，改为「公开分发器 + 私有单轨实现」。

### C.4 能力说明（GridView 单轨的限制与补偿）

| 能力项 | GridView 主轨 | 补偿 |
|---|---|---|
| 行级红 / 危险高亮 | 无 Color/Theme API | `State` 列 `⚠ 危险` / `⚠ 备选` / `● last` |
| 底部帮助行 | 无底部帮助区 | 菜单上方 Spectre 提示行 |
| 实时过滤 | 无键盘级过滤回调 | `-Focus Filter` 表格筛选框（`UI.GridViewFocus`） |
| `Disabled` 灰显 | 不支持 | `State` 标注 + 选中后阻断 |
| 独立「退出」行 | 表格不放 Exit 行 | `Esc` / `Ctrl-C`，返回 `$null` |

删除操作的不可逆性由 `Remove-TmuxSession` 中新增的 `Read-SpectreConfirm`（默认答案 `n`）独立保证；确认不可用时按「不删除」处理。

### C.5 保留文件的决定

- **`Invoke-MenuMachine.ps1` 已删除**（2026-10-18）— 它是 Ansi 降级轨的键盘引擎，随降级轨整体移除。
- **`Get-KeyboardFilter.ps1` 已删除**（v2.4 精简轮次）— 当时的结论是「实测确认其三个函数**无任何生产调用方**（仅自身引用与测试引用），但删除需连带改写 1499 行的 `ShellPrompt.Tests.ps1`，属于 AGENTS.md §5 明令避免的『不必要的重构』，本次不做」；后续精简轮次已将其删除。

### C.6 已知风险（未消除）

1. `-Focus Filter` 的实际手感只能在**交互式**终端验证；本次验证环境 stdin 被重定向，该路径只验证了「不抛异常」与配置传递。
2. PSTui 在**首次弹窗**时才绑定 Terminal.Gui v2；本仓库启动期检测只验证「当前未加载冲突版本」，真正的绑定结果要等弹窗。
3. `Out-ConsoleGridView` 未声明 `[OutputType()]`，返回值直接透传管线；`Invoke-GridViewPrompt` 做了「单对象 vs 单元素可枚举」的归一化，但 `.Value` 读取的端到端行为仍需交互环境实测。
4. 仓库既有测试是 Pester v3/v5 语法，本机安装的是 **Pester 6.2.0**（已移除 `Should Be` 旧断言、收紧了作用域），`ShellPrompt.Tests.ps1` / `Get-WttrWeather.Tests.ps1` / `Show-ProgressSpinner.Tests.ps1` 在 v6 下大面积失败。这是**迁移前就存在的基线问题**，不是本次改动引入的；本次新增的 `Get-ConsoleUiBackend.Tests.ps1` 已按 v5+ 语法编写，24/24 通过。

### C.7 ANSI 降级轨性能实测与加固（历史记录，降级轨已于 2026-10-18 移除）

> 背景: 用户反馈 `sss` 菜单「ui 有点卡顿」。本节记录对 **Ansi 降级轨** 的代码级根因验证、量化数据与加固措施, 结论是 **主轨已消解卡顿, 降级轨同步加固**。
>
> **归档说明**: 本节为**历史记录**，保留以说明卡顿问题的根因分析过程。自 2026-10-18 起 Ansi 降级轨已整体移除，本节描述的 `Clear-AnsiScreen` / `New-AnsiLayout` / `Write-MenuItem` / `Invoke-MenuMachine` 等加固产物**均已随降级轨删除**，当前控制台 UI 只有 GridView 一条渲染路径。

#### C.7.1 旧行为的根因（代码级验证）

1. **每按键整屏清屏**: `Private/Invoke-MenuMachine.ps1`（已删除）的主循环在每次按键后调用 `Show-AnsiLayout`, 旧实现内每帧执行 `[Console]::Clear()` —— 整屏擦除后**全帧重绘**。
2. **每帧固定重绘整屏行数**: 布局为 Header 4 行 + Main N 行 + Footer 2 行, 实测满帧 `LinesPerFullFrame = 21` 行 (N 与菜单项数量相关, 帧行数**随内容变化**, 但绘制行数恒等于整帧行数, 没有「只重画变化行」的机制)。
3. **每帧重建布局字符串**: 旧实现每帧重新执行 `New-AnsiLayout` 并重新拼接全部行字符串, 没有「内容未变则复用」判定。
4. **逐行 `Write-Host` 刷屏**: 每行一次宿主写入, 无批量提交。
5. **无 sleep, 无重复 `SetCursorPosition`**: 渲染循环中没有节流/退避, 也没有多余的显式光标定位调用 (行定位由每行的 `ESC[<行>;<列>H` 绝对定位完成)。

#### C.7.2 量化数据（非 TTY 环境，stdout/stderr 重定向到文件；单次统一复测，2026-10-17 20:51）

| 指标 | 实测值 | 说明 |
|---|---|---|
| 满帧重绘行数 | `21` 行/帧 | Header 4 + Main 15 + Footer 2 |
| 满帧重绘（`Show-AnsiLayout`, 100 帧均值） | `3.5612 ms/帧` | 含向重定向 stdout 写 21 行的开销 |
| 只重绘 3 行（100 帧均值） | `0.3769 ms/帧` | 同口径, 满帧约为其 **9.4 倍** |
| `Show-AnsiLayout` 连续 200 帧 | `4.2377 ms/帧`, stderr **0 字节** | 加固后 |
| 裸 `[Console]::Clear()` 连续 200 次（加固前行为） | stderr **98,200 字节**, 抛 `MethodInvocationException: 句柄无效。` | 每帧向 stderr 刷一次异常文本 |
| 单项渲染（完整颜色表, 未选中） | `198.68 µs/次` | 2000 次均值, 7 个语义色键全部命中 |
| 单项渲染（完整颜色表, 选中） | `171.60 µs/次` | 2000 次均值 |
| 单项渲染（颜色表残缺） | `1045.44 µs/次` | 缺键回落 `Get-CachedConfig` |
| 单项渲染（每项调用 `Resolve-MenuColorTable`） | `997.01 µs/次` | 对照: 内联查表 `166.44 µs/次` → 证明「会话级一次性补表」的必要性 |
| 渲染输出一致性 | `RenderOutputIdentical = True` | 完整表 vs 残缺表渲染结果**逐字节一致** |
| 颜色表键 | 7 键 | `Accent` / `Danger` / `Muted` / `Primary` / `Rst` / `SelectedBg` / `Warning` |

> 说明: 表中所有耗时均在 stdout 被重定向到文件的条件下测得, 因此**包含**写文件的开销, 绝对值偏大; 但同口径的相对比较（满帧 vs 增量 3 行、完整表 vs 残缺表、内联查表 vs 每项解析）有效。真实 TTY 下的帧率手感无法在自动化环境量化, 需按 C.7.7 人工确认。

#### C.7.3 结论

- **主轨已消解卡顿**: 三个交互菜单（主机选择 / 会话管理 / tmux 会话列表）默认全部走 `GridView` 主轨 (PSTui `Out-ConsoleGridView`), 手写 ANSI 只在降级场景出现。因此「ui 卡顿」在正常终端下**已不再是用户可感知项**。
- **降级轨存在明确可修的性能问题**（整屏 `Clear()` + 每帧全量重绘 + 颜色表缺失导致逐项回查配置), 且修复范围**不触碰主轨**, 因此本次做了加固, 而不是「为了做事而改代码」。

#### C.7.4 加固内容（降级轨, 主轨零影响）

| 改动 | 文件 | 效果 |
|---|---|---|
| 新增 `Clear-AnsiScreen`: 包裹 `[Console]::Clear()` 并 try/catch, 同时把帧底行锚点 `$script:AnsiFrameBottomRow` 归零 | `Private/Clear-AnsiScreen.ps1`（**新增, 后已随降级轨删除**） | 非 TTY 下**不抛异常**, stderr 噪声 `98,200 字节 → 0 字节`（同一次 200 帧对照） |
| 所有裸 `[Console]::Clear()` 调用点改走 `Clear-AnsiScreen` | `Invoke-MenuMachine.ps1` / `Invoke-ConsoleMenu.ps1`（均已删除） | 消除异常刷屏 |
| 渲染前用 `Resolve-MenuColorTable` 补全 7 个语义色键 (Accent/Danger/Muted/Primary/Rst/SelectedBg/Warning) | `Private/Write-MenuItem.ps1`（已删除） | 消除逐项 `Get-CachedConfig` 回查, 缺失键一次性解析 |
| 渲染器颜色表改为「完整表」传入, `Write-MenuItem` 保持内联查表 (不引入每次调用的哈希表分配) | 同上 | 逐项渲染 `1045 µs → 199 µs`（残缺表 → 完整表), 渲染结果逐字节一致 |
| `Show-AnsiLayout` 改为**首帧才整屏清**, 其余帧逐行 `ESC[<行>;1H ESC[2K` 覆盖; 帧变矮时擦除残留行 | `Private/New-AnsiLayout.ps1`（已删除） | 帧底行实测 `8 → 8 → 7` (内容变矮时旧行被擦除), 不再每帧整屏抖动 |
| 默认渲染器从内联 scriptblock 抽为具名函数 `Invoke-MenuDefaultRender` (9 参数契约不变) | `Private/Invoke-MenuMachine.ps1`（已删除） | 消除 `PSReviewUnusedParameter` 告警, 契约向后兼容 |
| `New-AnsiLayout` 非 TTY 下宽度探测加 try/catch | 同上 | 修复无 `-Width`/`-Center` 时的「句柄无效。」崩溃 |

#### C.7.5 向后兼容性

- 对外契约**零变化**: `Show-HostSelector` / `Show-SessionManager` / `Show-TmuxSessionList` 仍返回带 `.Value` 的 `PSCustomObject` 或 `$null`; 键位语义、帮助面板、状态栏文案均未变。
- 渲染器契约**零变化**: 仍是 `($Layout, $VisibleItems, $SelectedIdx, $Filter, $Colors, $ExitLabel, $ExitSelected, $ExitUnselected, $ExitItem)` 9 个位置参数。
- 私有函数签名**零变化**: `Show-AnsiLayout -Layout/-StartRow`、`New-AnsiLayout`、`Add-MainLine`、`Set-FooterLine`、`Write-AnsiLine` 参数集未改。
- 本次新增的私有函数 (`Clear-AnsiScreen` / `Resolve-MenuColorTable` / `Invoke-MenuDefaultRender`) 均位于 `Private/` 下, 受 `ShellPrompt.psd1` 的 `FunctionsToExport` 白名单保护, **不会被导出**, 因此不影响「命令导出」黑名单测试与 Public API 稳定性。

#### C.7.6 验证

- Pester: `ShellPrompt.Tests.ps1` **162 通过 / 0 失败**（基线 154 + 新增 8 个用例); 全量套件 **250 通过 / 0 失败**（基线 242)。
- PSScriptAnalyzer: 改动文件 (`Clear-AnsiScreen.ps1` / `New-AnsiLayout.ps1` / `Invoke-MenuMachine.ps1` / `Invoke-ConsoleMenu.ps1` / `Write-MenuItem.ps1`) **0 findings**。模块全量仍有 45 条**历史遗留** findings (Warning 35 / Information 10 / Error 0), 与本次改动无关。
- 真实交互终端的帧率手感**无法在自动化环境量化** (stdin 被重定向), 需在真实终端按 C.7.7 清单人工确认。

#### C.7.7 人工验收清单（真实终端，单轨版）

1. 正常启动 `pwsh` 后执行 `sss` —— 菜单应为 **PSTui 表格视图** (唯一主轨), 上下键无明显延迟。
2. 管道/重定向场景 (如 `echo | pwsh -NoProfile -Command "sss"`) —— 应抛出**可定位的终止错误**（含功能名与主轨不可用原因），而不是「句柄无效。」异常刷屏。

---

### C.8 GridView 主题配色调整: 列头由青色底改为暗底绿字 (2026-10-18)

> 背景: 用户反馈 GridView 菜单中「Action / Desc / State」三列表头行被高亮成亮青色 (Cyan=112,199,209), 与整体绿主题不搭。
>
> 根因 (TG 2.4.10.0 IL 级实测): `TableView.RenderHeaderMidline` 取 `scheme = Style.HeaderScheme ?? GetScheme()`, 列头文字 = `hasFocus ? scheme.Focus : scheme.Normal`; PSTui 的 `OutGridViewWindow` 构造函数硬编码 `SchemeName='Base'`, 且 `TableStyle.HeaderScheme` 默认 `$null`, 因此列头**总是**走 `Scheme.Base.Focus`。v2.1 的 `Theme.Slots.Focus = @{ Fg='20,20,20'; Bg='112,199,209' }` (Cyan 底 + 近黑字) 是「两焦点态选中行一致」的设计, 副作用就是「列头有焦点时也是青色条」。

**新契约 (2026-10-18)**:

| 槽位 | 新配色 | 旧配色 | 作用 |
|------|--------|--------|------|
| `Focus` | `137,209,133` / `40,40,40` | `20,20,20` / `112,199,209` | 聚焦列头 + 表格有焦点时的选中行 |
| `Active` | `137,209,133` / `40,40,40` | `20,20,20` / `112,199,209` | 焦点不在表格时的选中行 (同 Focus) |
| `Highlight` | `137,209,133` / `40,40,40` | `20,20,20` / `112,199,209` | 高亮标记 (同 Focus/Active) |
| `Editable` | `137,209,133` / `20,20,20` | `230,180,80` / `30,30,30` | 可编辑区 (过滤框, 亮绿字 + 近黑底) |

其余 `Normal` / `HotNormal` / `HotFocus` / `HotActive` / `ReadOnly` / `Disabled` **完全不动** —— 它们已经是绿主题内的灰阶过渡, 改了反而无收益。

**修复后的视觉契约**:

- **列头与正文同为绿字** (`137,209,133`), 整张表与绿主题统一, 不再出现「列头青色 + 正文绿字」的割裂感。
- **两种焦点状态下的选中行高亮仍一致** (保留 v2.1 不变量): Focus 与 Active 仍然同色。
- **过滤框在焦点态下仍清晰可读**: `Editable` 槽位承载"输入区本身"的取色, 亮绿字 (`137,209,133`) + 近黑底 (`20,20,20`) 对比度高; TG 的 `TextField` 把 role Normal 映射到 role Focus, 故过滤框文字由 Focus 槽位承托 (`137,209,133` / `40,40,40`, 也可读)。
- **IL 注释同步重写**: [`Private/Initialize-Config.ps1`](../ShellPrompt/Private/Initialize-Config.ps1) 的 `UI.Theme` 域注释删掉旧"列头也是青色条"的副作用说明, 改写为新契约的来源与含义。

**验证**:

- Pester 全量 **244 Passed / 0 Failed** (基线 242 + 新增 3 个用例, 见 [`Tests/Set-TgColorScheme.Tests.ps1`](../ShellPrompt/Tests/Set-TgColorScheme.Tests.ps1)):
  - 「Focus 与 Active 应配置为完全相同的颜色」—— 追加断言 `Focus.Fg='137,209,133'` + `Focus.Bg='40,40,40'`。
  - 「Focus 槽位底色应不再含 Cyan」—— 锁定 `Focus.Bg != '112,199,209'`, 且 `Active.Bg` / `Highlight.Bg` 与 `Focus.Bg` 完全相等。
  - 「Editable 槽位应配为亮绿字 + 暗底」—— 锁定 `Editable.Fg='137,209,133'` + `Editable.Bg='20,20,20'`。
  - 「应用后槽位值应与配置一致」—— `Active` 由 `#141414`/`#70C7D1` 改为 `#89D185`/`#282828`。
- PSScriptAnalyzer 在改动文件 **0 新增**告警。
- 反射取 `Scheme.Base.Focus` / `Scheme.Base.Active` / `Scheme.Base.Normal` / `Scheme.Base.Editable` 真实 RGB 落地正确, 列头已无 Cyan 背景 (`112,199,209` 已从 Focus/Active/Highlight 中移除)。

**仍需人工验收**: 真实交互终端 (`pwsh` + Windows Terminal) 打开 `sss`, 确认「Action / Desc / State」三列表头在焦点态下为暗底亮绿字, 选中行同时为亮绿字 + 稍亮底 (`40,40,40`), 过滤框可读。本节描述的视觉确认无法在自动化环境量化 (stdin 被重定向, `Assert-ConsoleUiReady` 会抛可定位的终止错误)。

---

*文档结束*
