# AI Agent Instructions for PowerShell Environment Project

## 1. Project Overview
This repository is a PowerShell terminal environment enhancement project. 
The goal is to provide a **fast, clean, and extensible** PowerShell experience while maintaining compatibility across different environments.

**Supported environments:**
- PowerShell 7+ (Preferred) & Windows PowerShell 5.1 (Fallback)
- Windows, Linux, WSL
**Core Integrations:**
- `ShellPrompt` module, `ssh` helper commands, `tmux` session management, `starship`, `fnm` (Node.js).

## 2. Architecture & Directory Rules
- `Microsoft.PowerShell_profile.ps1`: **MUST ONLY** handle module loading, environment initialization, and startup configuration. **NEVER** put complex business logic here.
- `Public/`: Contains user-facing commands. MUST maintain stable command behavior, use clear PowerShell naming, and include help comments (`.SYNOPSIS`, etc.).
- `Private/`: Contains internal helper functions. **MUST NOT** be exposed to users. 

## 3. Development Guidelines
### Naming & Scope
- **ALWAYS** use approved PowerShell verbs (`Get-Verb`). (e.g., `Get-TmuxSession`, `Connect-SshHost`). **NEVER** use unapproved verbs like `test1` or `ssh123`.
- **NEVER** use global variables (`$global:`) without explicit architectural justification. **ALWAYS** prefer `$script:` or local scope.

### Configuration
- **NEVER** hard-code user preferences (e.g., Bad: `$Theme="starship"` | Good: `$config.Theme`).
- Follow Configuration Priority: `User configuration -> Default configuration`.
- User-specific settings MUST NOT be stored inside repository files.

### External Dependencies (`git`, `ssh`, `tmux`, `starship`, `fnm`)
Before calling external commands, you **MUST**:
1. Check if the command exists (`Get-Command`).
2. Provide clear error messages if missing.
3. **NEVER** silently fail.

### Specific Domain Rules (SSH & tmux)
- **SSH**: Changes MUST consider path/execution differences between Windows OpenSSH, Linux OpenSSH, and WSL.
- **tmux**: Changes MUST respect existing sessions, session naming, and reconnect behaviors. **CRITICAL: NEVER delete or destroy existing tmux sessions without explicit user confirmation.**

### Compatibility & Fallbacks
- Prefer feature detection over version checking.
- Ensure graceful fallbacks when a specific feature is unavailable in PS 5.1 or the current OS.

## 4. Testing & Documentation
- **Testing**: Before submitting changes, verify module loading (`Import-Module ./ShellPrompt`). Run tests via `Invoke-Pester` (Assume Pester v5 syntax). Any changes involving profile loading, SSH, or tmux MUST be flagged for manual testing.
- **Documentation**: Any user-visible changes or configuration updates MUST be documented in `README.md` (Usage examples, migration notes).

## 5. Agent Behavior & Change Policy
When modifying this repository, you **MUST**:
- **Inspect existing code** (Read related files) before editing to understand the design.
- **Keep changes minimal**: Avoid unnecessary refactoring, avoid adding heavy dependencies, and NEVER break existing commands without asking.
- **Explain yourself**: Briefly explain changed files and report testing results.
- **Ask first**: For large architectural changes, ask for permission before implementation.

## 6. Commit Convention
ALWAYS use Conventional Commits: `type(scope): message`
- **Types**: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`
- *Example*: `feat(tmux): add session rename support`
