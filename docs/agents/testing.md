> 本文件由根 AGENTS.md 路由触发加载。上级约束见根文件“三层边界”。

# 测试与文档（Testing & Documentation）

## 测试（Testing）

- **Testing**: Before submitting changes, verify module loading (`Import-Module ./ShellPrompt`). Run tests via `Invoke-Pester` (Assume Pester v5 syntax). Run PSScriptAnalyzer via `Invoke-ScriptAnalyzer -Path ./ShellPrompt -Recurse -Settings ./ShellPrompt/Settings.ScriptAnalyzer.psd1` (`-Path` is mandatory). Any changes involving profile loading, SSH, or tmux MUST be flagged for manual testing.

## 文档（Documentation）

- **Documentation**: Any user-visible changes or configuration updates MUST be documented in `README.md` (Usage examples, migration notes).
