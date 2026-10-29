# Changelog

All notable changes to this project are recorded in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

> **⚠️ 本文件已冻结为历史快照（2026-10-29 标注）**
>
> - 历史段曾永久丢失；现存条目按原样保留，**不再新增、重写或回填**。
> - `[Unreleased]` 及早期版本条目描述的是**当时**的实现，其中引用的部分文件（如 `Invoke-ConsoleMenu.ps1` / `Invoke-MenuMachine.ps1`）已在 v2.0 单轨化重构中移除，请勿将其当作现行设计依据。
> - 现行用户可见变更同步义务落在 `README.md` 与 PR 描述，规则见 [`docs/agents/testing.md`](../docs/agents/testing.md)。

## [Unreleased]

### Fixed

- **菜单按方向键闪退 (v2 字节级 CSI 重组)**: v1.3.2 遗留 bug,Windows Terminal + PS 5.1 + [`Invoke-ConsoleMenu`](ShellPrompt/Private/Invoke-ConsoleMenu.ps1) 路径下方向键 (`UpArrow/DownArrow/LeftArrow/RightArrow`) 被编码为多字节 CSI 序列 `ESC [ A/B/C/D` (3 字节),首字节 `ReadKey` 实证返回 **`VirtualKeyCode=27, Character=0x1B, Key=Escape`** (PS issue [#16443](https://github.com/PowerShell/PowerShell/issues/16443) — 关键点:**`vK=27` 而非 0**)。v1 修复 `80405b6` 基于错误的"`vK=0`"假设硬编码 `Key.Escape` 查表,在 PS 5.1 上从未触发 → 菜单仍闪退。

  **v2 方案**: 在 [`Invoke-MenuMachine.ps1`](ShellPrompt/Private/Invoke-MenuMachine.ps1) 引入字节级 CSI 重组层。新增 `ConvertTo-CsiArrowKey` 私有函数,签名 `ConvertTo-CsiArrowKey -FirstByte <ConsoleKeyInfo> -NextKeyProvider <scriptblock> -Consumed [ref]`:
  1. 首字节若 `Key != Escape` → 透传(Consumed=$false,主循环把 `$FirstByte` 仍当原键处理)
  2. 首字节若 `Key == Escape` → 同步从 `NextKeyProvider` 读字节 2,若非 `[` 视为真 ESC 退出(Consumed=$false,但字节 2 已被读)
  3. 字节 2 为 `[` → 再读字节 3,在 `arrowMap` (`A/B/C/D` → `UpArrow/DownArrow/RightArrow/LeftArrow`) 查表;命中则合成 `ConsoleKeyInfo` 返回(Consumed=$true),未命中视为非法 CSI(Consumed=$false)

  同步重写 `Send-MenuKey` 主循环:发现首字节是 ESC 时,**直接调用 `ConvertTo-CsiArrowKey`** 而非任何 `vK/Key` 预判分支(老 `Key→vK` 查表路径已删除)。`[ref]$Consumed` 跨 `NextKeyProvider` 闭包写回主循环 — 真 ESC 让主循环退出(向 L150 ESC 分支走),伪 ESC 重组为方向键继续主循环。

  Pester 覆盖: 5 个 `Send-MenuKey` 边界 case (4 方向键 + Key.Escape 对照) + 7 个 `ConvertTo-CsiArrowKey` 字节重组 case (ESC+[+A/B/C/D 各方向、字节 1 非 ESC 透传、ESC+非[ 视为真 ESC、ESC+[+非法字节)。最终 **134/134 全绿** (127 原有 + 5 Send-MenuKey + 7 ConvertTo-CsiArrowKey, Pester 3.4.0)。

### Changed

- **`Invoke-Reload` 增强**: 修复了 v1.3.1 遗留的 PSScriptAnalyzer 抑制属性误用(原本作为 `param()` 前坬儿属性,会在 PS 5.1 拋语法错误),现改为在函数体内并补充 `try/catch` 包裹重载逻辑,避免重载失败时中断调用方。新增 `-Quiet` 开关用于脚本/管道场景不打印成功提示。详见 [`Invoke-Reload.ps1`](ShellPrompt/Public/Invoke-Reload.ps1)。

### Removed

- **热重载 watcher(FSW) 方案**: v1.3.3 探索中的 `Private/Start-HotReloadWatcher.ps1` 拆解为 ~160 行复杂代码(`Register-ObjectEvent` + `ThreadPool Timer` + 跨 runspace `SessionState` 读写)仍未能在 PS 5.1 下被手动烟测验证触发。Pester 的 126/126 覆盖虚高(测试本身走 `$script:HotReloadSuppressed=$true` 提前 return,从未实际 cover 到 watcher 订阅路径)。为遵守"小而深"模块边界,本版本不包含自动热重载;请开发者改完源码后手动跑 `Invoke-Reload`。

## [1.3.2] - 2026-10-01

### Fixed

- **远程 tmux 探测的 false negative**: v1.3.1 在 [`Get-TmuxSessions.ps1`](ShellPrompt/Private/Get-TmuxSessions.ps1) 的探针命令为 `TMUX_BIN=$(command -v tmux 2>/dev/null || echo /usr/bin/tmux)`,只覆盖 `/usr/bin/tmux` 一条硬编码兜底路径。当远端 tmux 装在 `/usr/local/bin/tmux` / `/snap/bin/tmux` / `/opt/homebrew/bin/tmux` / `/usr/sbin/tmux` 等其他绝对路径且不在非交互 sshd `$PATH` 中时,`command -v` 失败 → 兜底到 `/usr/bin/tmux`(该路径上其实没有)→ 后续 `tmux -V` 静默失败 → `$version` 解析空 → `Available=$false` → `Start-TmuxSession` 误报 "WARNING: 远程主机 X 未安装 tmux(或探测失败)"。hotfix 将兜底改为多路径穷举(`/usr/bin /usr/local/bin /snap/bin /opt/homebrew/bin /usr/sbin`),命中第一个可执行即用,在用户 `debian` 主机(实测 `/usr/bin/tmux` 可用)烟测通过:`Get-TmuxAvailability -HostName debian -Force` 返回 `Available=True, Version=3.5a, ExitCode=0`。

## [1.3.1] - 2026-10-01

### Fixed

- **模块加载失败回归**: v1.3.0 在 [`Invoke-MenuMachine.ps1`](ShellPrompt/Private/Invoke-MenuMachine.ps1) 注入 BOM 抑制属性时,P4-3a 批量脚本误把一个文件级 `[Diagnostics.CodeAnalysis.SuppressMessageAttribute()]` 写在第 11 行,而该行不存在 `function` 头 — 形成"孤儿属性"。PowerShell 5.1 解析器在 `Import-Module ShellPrompt` 阶段报 3 条 `WARNING: Unexpected attribute / Unexpected token 'param' / Unexpected token '}'`,导致 `New-MenuContext` 函数从未被定义。hotfix 将孤儿属性包裹到真正的 `function New-MenuContext { ... }` 函数体中(放在 `[CmdletBinding()]` 之前),与模块内其余函数风格一致,并补全 35 个 `.ps1` 中 BOM 抑制属性的换行格式(属性独占一行,`param(` 独占一行,消除与未来更多抑制属性堆叠时的脆弱性)。

## [1.3.0] - 2026-10-01

### Fixed

- **静态分析清零**: PSScriptAnalyzer 警告从 99 → 0。其中 36 条以源码级 `[Diagnostics.CodeAnalysis.SuppressMessageAttribute()]` 抑制（35 条 `BOM` + 1 条 `PSAvoidUsingPositionalParameters`），63 条真修复覆盖 8 类规则：
  - `PSUseShouldProcessForStateChangingFunctions`(14) — 14 个 `New-*`/`Set-*`/`Remove-*`/`Start-*`/`Update-*` 函数增加 `SupportsShouldProcess=$true` + 早返 `ShouldProcess(...)` 守卫
  - `PSUseSingularNouns`(5) — 随 P4-3b 重构自动消除
  - `PSReviewUnusedParameter`(11) — 移除 5 个真正未用形参、保留 6 个公开 API 形参并加注释
  - `PSUseOutputTypeCorrectly`(10) — 修正 7 个 `[OutputType()]` 标注与实际返回类型不匹配，移除 3 个多余标注
  - `PSAvoidUsingEmptyCatchBlock`(8) — 8 个 `catch { }` 替换为有意义的恢复或日志分支
  - `PSUseDeclaredVarsMoreThanAssignments`(6) — 6 个"仅赋值一次"变量改用 `ReadOnly`/`[void]` 显式语义
  - `PSUseCorrectCasing`(5) — `Tests/` 目录内 5 处 `Get-Verb` 大小写与批准动词对齐
  - `PSUseToExportFieldsInManifest`(1) — [`ShellPrompt.psd1`](ShellPrompt/ShellPrompt.psd1:21) `AliasesToExport = '*'` 收窄为 `@()`
  - `Register-ArgumentCompleter` 回调中 `commandAst` / `cursorPosition` 改用 `$null = ...` 静默引用，避免 `PSReviewUnusedParameter` 误报（运行时由 PowerShell 补全基础架构注入）
- **Pester 全绿回归**: 122/122 测试在 P4 清理后仍全部通过 ✅
- **修复 v1.2.0 残留误改**: `Start-TmuxSession.ps1` 中残留的文件级 `[CmdletBinding(SupportsShouldProcess=$true)]` 行（v1.2.0 自动重写脚本误插）已下沉到 `function Start-TmuxSession` 函数体内，恢复 PS 5.1 dot-source 解析

### Changed

- **模块版本提升**: `ModuleVersion` 从 `1.2.0` 更新为 `1.3.0`
- **PSScriptAnalyzer 配置基线**:
  [`Settings.ScriptAnalyzer.psd1`](ShellPrompt/Settings.ScriptAnalyzer.psd1) 8 条规则与本次真修复保持一一对应，可被 `Invoke-ScriptAnalyzer -Settings ./ShellPrompt/Settings.ScriptAnalyzer.psd1` 复现
- **SupportsShouldProcess 模式固化**: 14 个状态变更函数采用统一模板
  (`[CmdletBinding(SupportsShouldProcess=$true)]` + 早返 `if (-not $PSCmdlet.ShouldProcess(...)) { return ... }`),
  在 `Start-TmuxSession` / `New-TmuxSession` / `Remove-TmuxSession` / `New-RandomSessionName` 等函数中可复用

### Added

- **函数拆分**: `Invoke-SshCommand` 拆分为 [`Get-SshArgs`](ShellPrompt/Private/Get-SshArgs.ps1)、[`Invoke-SshCaptureOutput`](ShellPrompt/Private/Invoke-SshCaptureOutput.ps1) 和主干函数
- **子命令抽取**: `Start-TmuxSession` 拆分为 [`Connect-TmuxSession`](ShellPrompt/Private/Connect-TmuxSession.ps1)、[`New-TmuxSession`](ShellPrompt/Private/New-TmuxSession.ps1)、[`Remove-TmuxSession`](ShellPrompt/Private/Remove-TmuxSession.ps1) 三个子函数
- **工具函数抽取**: 新增 [`Save-OriginalTerminalState`](ShellPrompt/Private/Save-OriginalTerminalState.ps1)、[`ConvertTo-SshEscapedString`](ShellPrompt/Private/ConvertTo-SshEscapedString.ps1)、[`Test-SshHostName`](ShellPrompt/Private/Test-SshHostName.ps1)
- **PSScriptAnalyzer 配置**: 新增 [`Settings.ScriptAnalyzer.psd1`](ShellPrompt/Settings.ScriptAnalyzer.psd1)，含 8 条活跃规则 + 1 条排除规则

### Changed

- **消除全局变量 `$Global:LastSshHost`**: 迁移至 `$script:Config.SSH.LastHost`，通过配置系统持久化管理
- **消除重复 dot-source**: `Invoke-SshCommand.ps1` 和 `Start-SshInteractive.ps1` 中移除 `Reset-TerminalMode.ps1` 重复引用
- **统一错误处理**: `Start-TmuxSession` 中 `Write-Host` 警告消息改为 `Write-Warning`（符合非终止性错误约定）
- **补充 `[OutputType()]` 注解**: 覆盖模块内全部 24 个函数，标注输出类型（`[void]`、`[string]`、`[object]`、`[PSCustomObject]`、`[hashtable]`、`[string[]]`、`[bool]`）
- **Pester 测试扩展**: 新增 8 个测试（ConvertTo-SshEscapedString 3 例 + Test-SshHostName 4 例 + 新增私有函数导出检查 9 项）
- **模块版本提升**: `ModuleVersion` 从 `1.1.0` 更新为 `1.2.0`

### Fixed

- **Pester v5 测试骨架**: 新增 [`ShellPrompt/Tests/ShellPrompt.Tests.ps1`](ShellPrompt/Tests/ShellPrompt.Tests.ps1)，
  包含模块导入、命令导出、Verb-Noun 合规性和配置访问测试
- **多终端复用器支持**: 新增 [`Get-MultiplexerSessions`](ShellPrompt/Private/Get-TmuxSessions.ps1:49) 和 [`Test-MultiplexerAvailable`](ShellPrompt/Private/Get-TmuxSessions.ps1:120) 函数，支持检测 tmux、screen、byobu
- **用户配置覆盖**: 支持 `~/.ShellPrompt/config.ps1` 覆盖默认配置，使用 [`Merge-Hashtable`](ShellPrompt/Private/Initialize-Config.ps1:78) 实现深度合并
- **TUILogger 增强**: [`Write-TUILog`](ShellPrompt/Private/TUILogger.ps1:246) 新增 `$Source` 参数，支持结构化字段日志
- **延迟加载优化**: TUILogger 和 TUIPerformanceState 模块按需加载，减少模块初始化开销
- **SSH 配置 mtime 缓存**: [`Get-SshConfigHosts`](ShellPrompt/Private/Get-SshConfigHosts.ps1:3) 增加基于文件 mtime 的脚本级缓存，Tab 补全不再每次重读 `~/.ssh/config`

## [1.2.0] - 2025-09-15

### Added

- **函数拆分**: `Invoke-SshCommand` 拆分为 [`Get-SshArgs`](ShellPrompt/Private/Get-SshArgs.ps1)、[`Invoke-SshCaptureOutput`](ShellPrompt/Private/Invoke-SshCaptureOutput.ps1) 和主干函数
- **子命令抽取**: `Start-TmuxSession` 拆分为 [`Connect-TmuxSession`](ShellPrompt/Private/Connect-TmuxSession.ps1)、[`New-TmuxSession`](ShellPrompt/Private/New-TmuxSession.ps1)、[`Remove-TmuxSession`](ShellPrompt/Private/Remove-TmuxSession.ps1) 三个子函数
- **工具函数抽取**: 新增 [`Save-OriginalTerminalState`](ShellPrompt/Private/Save-OriginalTerminalState.ps1)、[`ConvertTo-SshEscapedString`](ShellPrompt/Private/ConvertTo-SshEscapedString.ps1)、[`Test-SshHostName`](ShellPrompt/Private/Test-SshHostName.ps1)
- **PSScriptAnalyzer 配置**: 新增 [`Settings.ScriptAnalyzer.psd1`](ShellPrompt/Settings.ScriptAnalyzer.psd1)，含 8 条活跃规则 + 1 条排除规则
- **多终端复用器支持**: 新增 [`Get-MultiplexerSessions`](ShellPrompt/Private/Get-TmuxSessions.ps1:49) 和 [`Test-MultiplexerAvailable`](ShellPrompt/Private/Get-TmuxSessions.ps1:120) 函数，支持检测 tmux、screen、byobu
- **用户配置覆盖**: 支持 `~/.ShellPrompt/config.ps1` 覆盖默认配置，使用 [`Merge-Hashtable`](ShellPrompt/Private/Initialize-Config.ps1:78) 实现深度合并
- **TUILogger 增强**: [`Write-TUILog`](ShellPrompt/Private/TUILogger.ps1:246) 新增 `$Source` 参数，支持结构化字段日志
- **延迟加载优化**: TUILogger 和 TUIPerformanceState 模块按需加载，减少模块初始化开销
- **SSH 配置 mtime 缓存**: [`Get-SshConfigHosts`](ShellPrompt/Private/Get-SshConfigHosts.ps1:3) 增加基于文件 mtime 的脚本级缓存，Tab 补全不再每次重读 `~/.ssh/config`

### Changed

- **消除全局变量 `$Global:LastSshHost`**: 迁移至 `$script:Config.SSH.LastHost`，通过配置系统持久化管理
- **消除重复 dot-source**: `Invoke-SshCommand.ps1` 和 `Start-SshInteractive.ps1` 中移除 `Reset-TerminalMode.ps1` 重复引用
- **统一错误处理**: `Start-TmuxSession` 中 `Write-Host` 警告消息改为 `Write-Warning`（符合非终止性错误约定）
- **补充 `[OutputType()]` 注解**: 覆盖模块内全部 24 个函数，标注输出类型（`[void]`、`[string]`、`[object]`、`[PSCustomObject]`、`[hashtable]`、`[string[]]`、`[bool]`）
- **Pester 测试扩展**: 新增 8 个测试（ConvertTo-SshEscapedString 3 例 + Test-SshHostName 4 例 + 新增私有函数导出检查 9 项）
- **模块版本提升**: `ModuleVersion` 从 `1.1.0` 更新为 `1.2.0`

### Fixed

- 修复 SSH 命令中 `StrictHostKeyChecking=no` 缺失导致的首次连接问题
- 修复远程 tmux 会话获取失败时的空值处理

## [1.1.0] - 2025-06-30

### Added

- **Pester v5 测试骨架**: 新增 [`ShellPrompt/Tests/ShellPrompt.Tests.ps1`](ShellPrompt/Tests/ShellPrompt.Tests.ps1)，
  包含模块导入、命令导出、Verb-Noun 合规性和配置访问测试

### Changed

- **重命名 `reload` → `Invoke-Reload`**: 函数名现已符合 Verb-Noun 规范（`Get-Verb` 批准动词），
  函数体采用 K&R 大括号风格，补充了完整的 `.SYNOPSIS` 帮助注释
- **移除冗余 `Export-ModuleMember`**: [`ShellPrompt.psm1`](ShellPrompt/ShellPrompt.psm1) 中不再包含
  `Export-ModuleMember` 语句，由 `.psd1` 的 `FunctionsToExport` 完全控制导出
- **移除冗余 `Set-ProfileAliases.ps1`**: `ssh-copy-id` 别名已由 `Microsoft.PowerShell_profile.ps1` 以
  `-Scope Global` 注册，模块内不再重复定义
- **统一脚本级缓存变量命名**: 去掉 `$_` 下划线前缀，全部使用 `$script:` 作用域限定。
  涉及 [`Get-SshConfigHosts`](ShellPrompt/Private/Get-SshConfigHosts.ps1)、
  [`Get-TmuxSessions`](ShellPrompt/Private/Get-TmuxSessions.ps1)、
  [`Initialize-Config`](ShellPrompt/Private/Initialize-Config.ps1) 和
  [`Show-UserScoopLogo`](ShellPrompt/Public/Show-UserScoopLogo.ps1)
- **统一大括号风格为 K&R**: `Invoke-Reload`、`Start-TmuxSession`、`Invoke-ConsoleMenu`
  中的函数定义统一采用左大括号与函数名同行
- **补充 Public 函数帮助注释**: 为 [`Copy-SshPublicKey`](ShellPrompt/Public/Copy-SshPublicKey.ps1)、
  [`Invoke-Reload`](ShellPrompt/Public/Invoke-Reload.ps1)、
  [`Show-UserScoopLogo`](ShellPrompt/Public/Show-UserScoopLogo.ps1) 和
  [`Start-TmuxSession`](ShellPrompt/Public/Start-TmuxSession.ps1) 补充了标准的
  `.SYNOPSIS` / `.DESCRIPTION` / `.PARAMETER` / `.EXAMPLE` 帮助头
- **模块版本提升**: `ModuleVersion` 从 `1.0.0` 更新为 `1.1.0`
- **TUIPerformanceState 算法优化**: `ReportFrame()` 中 `CalculateFrameTimeStats()` 从 **O(n) foreach 改为 O(1) 增量统计**（维护 `_sum`/`_count`/peak/min，窗口出队按需重建），每帧统计耗时与窗口大小解耦
- **TUIPerformanceState 缓存**: `GetSummary()` 引入 `_summaryDirty` 标志缓存摘要哈希表，连续渲染场景下避免重复 `Round`/Date 差值计算
- **TUIPerformanceState 字段去重**: 移除构造函数中重复的 `_cachedSummary`/`_summaryDirty` 赋值（已统一在类成员处声明）
- **Reset-TerminalMode 批量化**: 6 次 P/Invoke `[Console]::Write` 合并为 1 次单字符串写入，减少 syscall 开销
- **删除死代码**: 移除 `Set-ProfileAliases.ps1` 中极少使用且易与 PowerShell 自然语法冲突的 `..` / `~` 函数别名
- **错误处理增强**: SSH 连接、文件读写添加 try-catch 处理，避免阻塞模块加载
- **SSH 配置解析**: [`Get-SshConfigHosts`](ShellPrompt/Private/Get-SshConfigHosts.ps1:3) 增加错误处理和日志记录
- **TUILogger I/O 合并**: [`RotateIfNeeded`](ShellPrompt/Private/TUILogger.ps1:94) 将 `Test-Path` + `Get-Item` 两次文件系统调用合并为单次 `Get-Item -ErrorAction SilentlyContinue`，热路径上减少一次 stat
- **Start-TmuxSession 函数提升**: 将内部辅助函数 `New-RandomSessionName` 与 `$sessionPrefix` 提升到模块作用域（`$script:` + 模块级函数），避免每次调用重复创建闭包
- **Initialize-Environment switch 重构**: 时间问候嵌套 `if/elseif` 改为 `switch ($true) { ... }` 模式；`Get-Random -Max 100` 合并为单次调用并改用 `-Minimum 0 -Maximum 100`（与原行为等价）
- **Show-UserScoopLogo Write-Host 批量化**: `Initialize-Environment.ps1` 中 10 次 `Write-Host` 合并为 1 次单字符串写入（数组 + `-join "\n"`）。Windows console 上每次 `Write-Host` 约 20-40ms 启动开销，单字符串化预计节省 ~250-350ms
- **Show-UserScoopLogo 默认参数预解引用**: 将 5 个默认值从 `$global:UserScoop_CONF.XXX` 表达式树（每次调用重算）改为模块顶部 `$script:Cfg*` 局部变量，节省每次调用的 ExpressionAst 求值开销
- **Test-Path + Get-Item 合并**: `Initialize-Config.ps1` 中用户配置检测改用 `Get-Item -ErrorAction SilentlyContinue` 一次调用，热路径上减少一次 stat
- **ConvertFromJsonCompat 嵌套闭包内联**: 把内部嵌套的 `_ConvertRecursive` 重写为同函数内联的 `function _ConvertValue`，避免每次调用都重新解析/绑定嵌套 ScriptBlock；同时用 `+=` 数组替代 `ArrayList.Add`，消除逐次扩容

### Reverted

- **回滚 Initialize-Config `$script:` ScriptBlock 化**: 将 `Merge-UserConfig` / `Merge-Hashtable` / `Get-PowerShellExe` / `ConvertFromJsonCompat` 改写为模块作用域 ScriptBlock 会在 dot-source 后只赋值到 `$script:` 命名空间，而其他脚本（如 Import-Module 链）按名称查找函数时只能命中 `Function:` 驱动器，导致终端无法加载。已恢复为 `function` 定义形式，保留 `Test-Path` 合并 / `+=` 数组 / 嵌套函数简化这三项不影响 caller scope 兼容性的优化

## [1.0.0] - 2024-01-01

### Added

- 初始版本发布
- 远程 tmux 会话管理器 (`Start-TmuxSession`)
- SSH Config 主机名自动补全
- TUI 日志系统 (TUILogger)
- TUI 性能监控 (TUIPerformanceState)
- 终端环境初始化 (Initialize-Environment)
- PowerShell Profile 重载命令 (`reload`)
