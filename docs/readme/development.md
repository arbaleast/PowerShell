# 🛠️ 开发者指南

以下约束引自 [`AGENTS.md`](../../AGENTS.md) 及其路由的 [`docs/agents/`](../agents/) 子规约，所有贡献者必须遵守。本页是**可读摘录**；条目发生分歧时，以 `docs/agents/` 下的权威版本为准。

## 命名与作用域

> - **ALWAYS** use approved PowerShell verbs (`Get-Verb`). (e.g., `Get-TmuxSessions`, `Get-SshConfigHosts`). **NEVER** use unapproved verbs like `test1` or `ssh123`.
> - **NEVER** use global variables (`$global:`) without explicit architectural justification. **ALWAYS** prefer `$script:` or local scope.

## 函数分解与单一职责

> - **PREFER** small, focused functions over monolithic ones. When a function exceeds ~80 lines or handles multiple concerns, split it:
>   - `Invoke-SshCommand` → `Get-SshArgs` (arg building) + `Invoke-SshCaptureOutput` (capture I/O) + backbone (dispatch logic)
>   - `Start-TmuxSession` → `Show-TmuxTuiDashboard` → `Invoke-TmuxAttach` / `New-TmuxSession` / `Invoke-TmuxSessionDeletion`
> - **Shared utilities**: Extract reusable logic into `Private/` utility functions (e.g., `ConvertTo-SshEscapedString`, `Test-SshHostName`, `Save-OriginalTerminalState`).
> - **Terminal state pattern**: Use `Save-OriginalTerminalState` + `Reset-TerminalMode` in `try {} finally {}` for any SSH command that changes terminal encoding/TERM.

## 输出注解

> - **ALWAYS** add `[OutputType()]` annotation to every function. Use exact types: `[void]`, `[string]`, `[bool]`, `[object]`, `[PSCustomObject]`, `[hashtable]`, `[string[]]`.
> - **ALWAYS** add `[CmdletBinding()]` to every advanced function.

## 错误处理约定

> | 场景 | 方式 | 示例 |
> |------|------|------|
> | 参数校验 | `[ValidateScript()]` + `throw` | 非法主机名字符 |
> | 运行时致命错误 | `throw` (终止性) | 配置缺失、依赖不可用 |
> | 可恢复失败 | `Write-Warning` (非终止性) | SSH 超时、tmux 不可用 |
> | 外部命令缺失 | `Get-Command` 检查 → `Write-Warning` | tmux、ssh 未安装 |
> | **例外**: UI 渲染 | `Write-Host` 允许 | `Show-UserScoopLogo` |

## 配置

> - **NEVER** hard-code user preferences (e.g., Bad: `$Theme="starship"` | Good: `$config.Theme`).
> - Follow Configuration Priority: `User configuration -> Default configuration`.
> - User-specific settings MUST NOT be stored inside repository files.

## 外部依赖

> Before calling external commands, you **MUST**:
> 1. Check if the command exists (`Get-Command`).
> 2. Provide clear error messages if missing.
> 3. **NEVER** silently fail.

## SSH 与 tmux 红线

> - **SSH**: Changes MUST respect the **Windows-first** implementation constraint (见 [`agents/architecture.md`](../agents/architecture.md)): `ssh.exe` / `where.exe` / `$env:LOCALAPPDATA` 等 Windows 专有假设目前**不可用**于 Linux / WSL。
> - **tmux**: Changes MUST respect existing sessions, session naming, and reconnect behaviors. **CRITICAL: NEVER delete or destroy existing tmux sessions without explicit user confirmation.**

## 测试

> - **Testing**: Before submitting changes, verify module loading (`Import-Module ./ShellPrompt`). Run tests via `Invoke-Pester` (Assume Pester v5 syntax). Run PSScriptAnalyzer via `Invoke-ScriptAnalyzer -Path ./ShellPrompt -Recurse -Settings ./ShellPrompt/Settings.ScriptAnalyzer.psd1` (`-Path` is mandatory). Any changes involving profile loading, SSH, or tmux MUST be flagged for manual testing.

> **PSSA 已知约束**：[`Settings.ScriptAnalyzer.psd1`](../../ShellPrompt/Settings.ScriptAnalyzer.psd1) 中 `PSUseCorrectCasing` 的 `CheckCommands` 被置为 `$false`。原因是 PSScriptAnalyzer 1.25.0 的该规则在读取命令参数元数据时，会实例化 [`PwshSpectreConsole`](../../Modules/PwshSpectreConsole/2.6.3/PwshSpectreConsole.psm1) 的动态 `ValidateSet` 值生成器，而该生成器需要 Runspace，PSSA 在无 Runspace 的线程中调用即抛 `There is no Runspace available to run scripts in this thread`，导致**整个被扫描文件的扫描结果作废**（不只是该文件）。关闭后关键字 / 操作符 / 别名的大小写检查仍然生效，仅命令名与参数名的大小写检查被关闭。

## 提交规范

> ALWAYS use Conventional Commits: `type(scope): message`
> - **Types**: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`
> - *Example*: `feat(tmux): add session rename support`

