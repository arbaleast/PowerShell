> 本文件由根 [`AGENTS.md`](../../AGENTS.md) 文档导航按需路由加载；通用工作原则与安全边界见根文件。

# 开发规约（Development Guidelines）

## 命名与作用域（Naming & Scope）

- **ALWAYS** use approved PowerShell verbs (`Get-Verb`). (e.g., `Get-TmuxSessions`, `Get-SshConfigHosts`). **NEVER** use unapproved verbs like `test1` or `ssh123`.
- **NEVER** use global variables (`$global:`) without explicit architectural justification. **ALWAYS** prefer `$script:` or local scope.

## 函数拆分与单一职责（Function Decomposition & Single Responsibility）

- **PREFER** small, focused functions over monolithic ones. When a function exceeds ~80 lines or handles multiple concerns, split it:
  - `Invoke-SshCommand` → `Get-SshArgs` (arg building) + `Invoke-SshCaptureOutput` (capture I/O) + backbone (dispatch logic)
  - `Start-TmuxSession` → `Connect-TmuxSession` / `New-TmuxSession` / `Remove-TmuxSession` (one action per sub-function)
- **Shared utilities**: Extract reusable logic into `Private/` utility functions (e.g., `ConvertTo-SshEscapedString`, `Test-SshHostName`, `Save-OriginalTerminalState`).
- **Terminal state pattern**: Use `Save-OriginalTerminalState` + `Reset-TerminalMode` in `try {} finally {}` for any SSH command that changes terminal encoding/TERM.

## 输出注解（Output Annotations）

- **ALWAYS** add `[OutputType()]` annotation to every function. Use exact types: `[void]`, `[string]`, `[bool]`, `[object]`, `[PSCustomObject]`, `[hashtable]`, `[string[]]`.
- **ALWAYS** add `[CmdletBinding()]` to every advanced function.

## 错误处理约定（Error Handling Convention）

| Scenario | Method | Example |
|----------|--------|---------|
| Parameter validation | `[ValidateScript()]` + `throw` | Invalid hostname characters |
| Runtime fatal error | `throw` (terminating) | Config missing, dependency unavailable |
| Recoverable failure | `Write-Warning` (non-terminating) | SSH timeout, tmux not available |
| Missing external command | `Get-Command` check → `Write-Warning` | tmux, ssh not installed |
| **Exception**: UI rendering | `Write-Host` allowed | `Show-UserScoopLogo` |

## 配置（Configuration）

- **NEVER** hard-code user preferences (e.g., Bad: `$Theme="starship"` | Good: `$config.Theme`).
- Follow Configuration Priority: `User configuration -> Default configuration`.
- User-specific settings MUST NOT be stored inside repository files.

## 外部依赖（External Dependencies: `git`, `ssh`, `tmux`, `starship`, `fnm`）

Before calling external commands, you **MUST**:
1. Check if the command exists (`Get-Command`).
2. Provide clear error messages if missing.
3. **NEVER** silently fail.
