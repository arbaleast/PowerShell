# ⚡ 命令一览

ShellPrompt 模块导出 **5 个公开命令**。完整的使用场景见 [功能特点](features.md)，配置项见 [配置说明](configuration.md)。

## 可用性

| 时机 | 可直接使用 |
|------|------------|
| 新开 PowerShell 会话（已配置仓库 profile） | `ll`、`which`、`sss`、`ssh-copy-id`、`Start-TmuxSession`、`Copy-SshPublicKey`、`Show-UserScoopLogo` |
| ShellPrompt 模块加载后 | 上述命令 + `Update-Weather`、`Invoke-Reload` |

首次运行 `sss` 或 `ssh-copy-id` 时会自动加载 ShellPrompt 模块；也可以手动加载：

```powershell
Import-Module "$HOME\PowerShell\ShellPrompt\ShellPrompt.psd1"
```

> 手动 `Import-Module` 不会注册 `ll` / `which` / `sss` / `ssh-copy-id` 这些别名——它由 [`Microsoft.PowerShell_profile.ps1`](../../Microsoft.PowerShell_profile.ps1) 注册。

## 公开命令

| 命令 | 说明 | 参数 |
|------|------|------|
| `Show-UserScoopLogo` | 显示欢迎 Banner 与随机语录（启动时自动调用，一般无需手动执行） | `-QuotesPath`、`-ColorPrimary`、`-ColorAccent`、`-ColorMuted`、`-BorderColor` |
| `Start-TmuxSession` | 选择 SSH 主机并管理远端 tmux 会话 | `-HostName`（位置 0；主机名白名单校验）；支持 `-WhatIf` / `-Confirm` |
| `Copy-SshPublicKey` | 把本机 SSH 公钥追加到远端 `authorized_keys` | `-RemoteHost`（位置 0，必填）、`-IdentityFile`、`-Port`（默认 22） |
| `Update-Weather` | 绕过缓存拉取一次 wttr.in 天气并打印 | 无业务参数；支持 `-WhatIf` / `-Confirm` |
| `Invoke-Reload` | 重新加载 `$PROFILE` 和 ShellPrompt 模块 | `-Quiet`（不输出成功提示） |

### `Show-UserScoopLogo`

```powershell
Show-UserScoopLogo
```

参数留空时使用配置中的默认值（`Colors.*`、`Paths.Quotes`）；通常在 profile 启动阶段自动调用。

### `Start-TmuxSession`

```powershell
sss                 # 打开主机选择器
sss deb             # 跳过选择器，直接管理 ~/.ssh/config 中的 deb
```

- `-HostName` 对应位置参数；示例统一用位置参数 `sss <主机>`，首次调用最稳妥。
- 需要真实交互终端、本机 `ssh.exe`，以及远端已安装 tmux。
- 非交互终端（管道 / CI / 重定向）中调用会直接跳过仪表盘并给出警告，不会卡死。
- 也支持 PowerShell 通用参数 `-WhatIf` / `-Confirm`。

### `Copy-SshPublicKey` / `ssh-copy-id`

```powershell
ssh-copy-id user@example.com
ssh-copy-id user@example.com -IdentityFile ~/.ssh/id_ed25519.pub -Port 2222
```

- `-RemoteHost` 支持 `user@hostname` 形式，校验规则与 `Start-TmuxSession` 相同。
- 不传 `-IdentityFile` 时自动按 `id_ed25519.pub > id_ecdsa.pub > id_rsa.pub > id_dsa.pub` 查找。
- 依赖本机 `ssh.exe`；按 Windows 路径实现（`$env:USERPROFILE`）。

### `Update-Weather`

```powershell
Update-Weather
```

强制刷新一次天气缓存并打印单行结果（如 `Shanghai: 🌫 +18°C`）。网络失败或返回空内容时打印提示，不抛异常。需要网络；优先使用系统 `curl.exe`，缺失时回退到 `Invoke-RestMethod`。

### `Invoke-Reload`

```powershell
Invoke-Reload          # 重载并打印成功提示
Invoke-Reload -Quiet   # 静默模式（脚本 / 管道场景）
```

改完模块源码或 `$HOME/.ShellPrompt/config.ps1` 后使用，无需重启 PowerShell。原理是卸载 `ShellPrompt` 模块后重新执行 `$PROFILE`。需要 `$PROFILE` 存在；模块未加载时该命令本身也不可用，先运行一次 `sss` 或手动 `Import-Module`。

## 别名

别名由 [`Microsoft.PowerShell_profile.ps1`](../../Microsoft.PowerShell_profile.ps1) 以全局作用域注册，模块本身不导出别名。

| 别名 | 映射到 | 说明 |
|------|--------|------|
| `ll` | `Get-ChildItem` | 列目录 |
| `which` | `where.exe` | 仅 Windows |
| `sss` | `Start-TmuxSession` | tmux 会话管理器 |
| `ssh-copy-id` | `Copy-SshPublicKey` | 推送 SSH 公钥 |

## 常用组合

```powershell
# 新机器：先配置 profile，再打开管理器
sss

# 首次给新主机配置免密登录
ssh-copy-id user@example.com

# 修改配置后立即生效
Invoke-Reload

# 验证 wttr.in 是否可达
Update-Weather
```

## 依赖说明

| 命令 | 依赖 |
|------|------|
| `Start-TmuxSession` | 交互式终端、本机 OpenSSH 客户端（`ssh.exe`）、远端 tmux |
| `Copy-SshPublicKey` | 本机 OpenSSH 客户端（`ssh.exe`）、本地已有 SSH 密钥对 |
| `Update-Weather` | 网络；`curl.exe` 可选（缺失时回退 `Invoke-RestMethod`） |
| `Invoke-Reload` | `$PROFILE` 存在且指向仓库内的 profile |
| `Show-UserScoopLogo` | 无必需外部依赖；语录文件缺失时回退内置文案 |
