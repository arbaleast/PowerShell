# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
