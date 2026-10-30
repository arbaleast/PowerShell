> 本文件由根 [`AGENTS.md`](../../AGENTS.md) 文档导航按需路由加载；通用工作原则与安全边界见根文件。

# 领域规约：SSH 与 tmux（Specific Domain Rules）

## SSH

- **SSH**: Changes MUST respect the **Windows-first** implementation constraint (see [`architecture.md`](architecture.md)): `ssh.exe` / `where.exe` / `$env:LOCALAPPDATA` 等 Windows 专有假设目前**不可用**于 Linux / WSL, 改动不得默认其存在; 若要新增跨平台支持, 需同时更新 [`architecture.md`](architecture.md) 的平台声明。
- **目标地址白名单**: 任何进入 ssh 命令行的目标地址必须经 `Test-SshHostName` 白名单校验 —— 仅字母、数字、点、短横线、下划线, 且首字符必须是字母或数字。
  - **为什么**: ssh 的 getopt 会把以 `-` 开头的目标地址解析成选项, 于是 `-oProxyCommand=...` 会在**本机**执行命令。实测 `ssh -oProxyCommand="touch /tmp/x" somehost` 会在本机创建 `/tmp/x`（OpenSSH 9.2, Linux）。历史实现用否定式黑名单, 放行了该形态。
  - **怎么用**: 新增目标地址来源（命令行参数、`~/.ssh/config` 别名、脚本拼接等）时**必须复用该校验**, 不得另写规则; 需要 `user@host` 形式时传 `-AllowUserPrefix`（`Copy-SshPublicKey` 的 `-RemoteHost` 即此形态）。

## tmux

- **tmux**: Changes MUST respect existing sessions, session naming, and reconnect behaviors. **CRITICAL: NEVER delete or destroy existing tmux sessions without explicit user confirmation.**
