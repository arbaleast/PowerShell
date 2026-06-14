# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **多终端复用器支持**: 新增 [`Get-MultiplexerSessions`](ShellPrompt/Private/Get-TmuxSessions.ps1:49) 和 [`Test-MultiplexerAvailable`](ShellPrompt/Private/Get-TmuxSessions.ps1:120) 函数，支持检测 tmux、screen、byobu
- **用户配置覆盖**: 支持 `~/.ShellPrompt/config.ps1` 覆盖默认配置，使用 [`Merge-Hashtable`](ShellPrompt/Private/Initialize-Config.ps1:78) 实现深度合并
- **TUILogger 增强**: [`Write-TUILog`](ShellPrompt/Private/TUILogger.ps1:246) 新增 `$Source` 参数，支持结构化字段日志
- **延迟加载优化**: TUILogger 和 TUIPerformanceState 模块按需加载，减少模块初始化开销
- **SSH 配置 mtime 缓存**: [`Get-SshConfigHosts`](ShellPrompt/Private/Get-SshConfigHosts.ps1:3) 增加基于文件 mtime 的脚本级缓存，Tab 补全不再每次重读 `~/.ssh/config`

### Changed

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

### Fixed

- 修复 SSH 命令中 `StrictHostKeyChecking=no` 缺失导致的首次连接问题
- 修复远程 tmux 会话获取失败时的空值处理

## [1.0.0] - 2024-01-01

### Added

- 初始版本发布
- 远程 tmux 会话管理器 (`Start-TmuxSession`)
- SSH Config 主机名自动补全
- TUI 日志系统 (TUILogger)
- TUI 性能监控 (TUIPerformanceState)
- 终端环境初始化 (Initialize-Environment)
- PowerShell Profile 重载命令 (`reload`)
