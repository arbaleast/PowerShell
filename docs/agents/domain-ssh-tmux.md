> 本文件由根 [`AGENTS.md`](../../AGENTS.md) 文档导航按需路由加载；通用工作原则与安全边界见根文件。

# 领域规约：SSH 与 tmux（Specific Domain Rules）

## SSH

- **SSH**: Changes MUST respect the **Windows-first** implementation constraint (see [`architecture.md`](architecture.md)): `ssh.exe` / `where.exe` / `$env:LOCALAPPDATA` 等 Windows 专有假设目前**不可用**于 Linux / WSL, 改动不得默认其存在; 若要新增跨平台支持, 需同时更新 [`architecture.md`](architecture.md) 的平台声明。

## tmux

- **tmux**: Changes MUST respect existing sessions, session naming, and reconnect behaviors. **CRITICAL: NEVER delete or destroy existing tmux sessions without explicit user confirmation.**
