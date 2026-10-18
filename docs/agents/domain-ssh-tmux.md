> 本文件由根 AGENTS.md 路由触发加载。上级约束见根文件“三层边界”。

# 领域规约：SSH 与 tmux（Specific Domain Rules）

## SSH

- **SSH**: Changes MUST consider path/execution differences between Windows OpenSSH, Linux OpenSSH, and WSL.

## tmux

- **tmux**: Changes MUST respect existing sessions, session naming, and reconnect behaviors. **CRITICAL: NEVER delete or destroy existing tmux sessions without explicit user confirmation.**
