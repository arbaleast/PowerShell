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

### Changed

- **错误处理增强**: SSH 连接、文件读写添加 try-catch 处理，避免阻塞模块加载
- **SSH 配置解析**: [`Get-SshConfigHosts`](ShellPrompt/Private/Get-SshConfigHosts.ps1:3) 增加错误处理和日志记录

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
