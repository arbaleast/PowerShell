# ⚡ 命令一览

## 公开命令

| 命令 | 说明 | 关键参数 | 依赖 | 源文件 |
|------|------|----------|------|--------|
| `Show-UserScoopLogo` | 显示 ANSI 欢迎 Banner 及随机语录(委托 `New-WelcomeBanner` + `Get-RandomQuote`,带 mtime 缓存) | `-QuotesPath`、`-ColorPrimary`、`-ColorAccent`、`-ColorMuted`、`-BorderColor` | — | [`Show-UserScoopLogo.ps1`](../../ShellPrompt/Public/Show-UserScoopLogo.ps1) |
| `Start-TmuxSession` | 远程 tmux 会话交互式管理(进入后展示欢迎 banner + SSH 探测 / 会话刷新期间 spin 动画 + 超时控制) | `-HostName` | ssh、tmux | [`Start-TmuxSession.ps1`](../../ShellPrompt/Public/Start-TmuxSession.ps1) |
| `Update-Weather` | **绕过缓存**强制拉取一次 wttr 短格式(`?format=3`)并 `Write-Host` 输出单行天气, 用于手动验证 wttr.in 可达性(结果会覆盖模块单槽缓存, 下次开菜单会重新拉取) | — | curl.exe / `Invoke-RestMethod` | [`Update-Weather.ps1`](../../ShellPrompt/Public/Update-Weather.ps1) |
| `Copy-SshPublicKey` | 一键推送 SSH 公钥到远程主机 | `-RemoteHost`、`-IdentityFile`、`-Port` | ssh | [`Copy-SshPublicKey.ps1`](../../ShellPrompt/Public/Copy-SshPublicKey.ps1) |
| `Invoke-Reload` | 一键重载 PowerShell 配置 | `-Quiet`（脚本/管道场景静默） | — | [`Invoke-Reload.ps1`](../../ShellPrompt/Public/Invoke-Reload.ps1) |

## 内部封装（不通过 `FunctionsToExport` 暴露）

| 函数 | 说明 | 关键参数 | 源文件 |
|------|------|----------|--------|
| `Invoke-WithProgress` | 执行 `-ScriptBlock`,期间显示 Spectre 进度动画(单轨 `Invoke-SpectreCommandWithStatus`);异常统一重拋;不提供超时/轮询参数 | `-ScriptBlock`、`-Style` | [`Invoke-WithProgress.ps1`](../../ShellPrompt/Private/Invoke-WithProgress.ps1) |

> **P2 UX 流程**(`Start-TmuxSession` 启动后顺序):
> 1. **欢迎 banner** — `New-WelcomeBanner` 渲染主机名 + 随机语录(见 [`New-WelcomeBanner.ps1`](../../ShellPrompt/Private/New-WelcomeBanner.ps1))
> 2. **SSH 探测 + 会话刷新** — `Invoke-WithProgress` 包覆,期间显示 Spectre 进度动画;无超时参数(见 [`Invoke-WithProgress.ps1`](../../ShellPrompt/Private/Invoke-WithProgress.ps1))
> 3. **主机 / 会话选择** — `Show-HostSelector` / `Show-SessionManager` 由 GridView 主轨驱动(见 [`Invoke-GridViewMenu.ps1`](../../ShellPrompt/Private/Invoke-GridViewMenu.ps1))
> 4. **连接 / 附着** — `Connect-TmuxSession` / `New-TmuxSession` / `Remove-TmuxSession` 分派,期间 `Save-OriginalTerminalState` + `Reset-TerminalMode` 在 `try/finally` 中保护终端态

## 别名

| 别名 | 映射命令 |
|------|----------|
| `ll` | `Get-ChildItem` |
| `which` | `where.exe` |
| `sss` | `Start-TmuxSession` |
| `ssh-copy-id` | `Copy-SshPublicKey` |

> 别名由 `Microsoft.PowerShell_profile.ps1` 以 `-Scope Global` 注册，模块内不再定义。

## 🛠️ 开发模式重载

改完 `ShellPrompt/Private/*.ps1` / `Public/*.ps1` / `ShellPrompt.psm1` / `~/.ShellPrompt/config.ps1` 后,**不需要重启 PowerShell**,跑一次:

```powershell
Invoke-Reload          # 默认: 重载 PROFILE + ShellPrompt, 打印 " [OK] ..." 提示
Invoke-Reload -Quiet   # 静默模式(脚本/管道场景用)
```

原理: 卸载 `ShellPrompt` 模块 + dot-source `$PROFILE`,后者中的 `Ensure-ShellPrompt` 会重新 `Import-Module` 拉起最新代码(见 [`Microsoft.PowerShell_profile.ps1`](../../Microsoft.PowerShell_profile.ps1))。

> **为什么不做 FileSystemWatcher 自动重载?**
> 一次性 ~150 行代码 + EventManager + ThreadPool + 跨 runspace SessionState 读写,
> 远超本项目"小而深"模块边界;且 Pester 虚高 + scope 链路过深,
> 实测 7 次重试仍无法稳定 fire。手动 `Invoke-Reload` 成本低、可预测。
>
> **推荐编辑器工作流**: VSCode / vim 配 `chokidar` / `watchexec` 监听 `ShellPrompt/*.ps*`,
> 存盘后自动调 `Invoke-Reload -Quiet`(项目根 `.vscode/settings.json` 或 `~/.config/watchexec/config.toml`)。

