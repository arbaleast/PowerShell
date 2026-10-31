# ShellPrompt

面向 **PowerShell 7.6+** 的终端增强工具：把 SSH 主机选择、tmux 会话管理、公钥部署收进终端里的全屏交互界面，同时改善 PowerShell 的启动问候、提示符与开发工具链初始化。

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](ShellPrompt/LICENSE)
[![PowerShell 7.6+](https://img.shields.io/badge/PowerShell-7.6%2B-blue.svg)](https://github.com/PowerShell/PowerShell)
![Platform: Windows](https://img.shields.io/badge/Platform-Windows-0078D4.svg)

> 本仓库按 **Windows** 设计并在 Windows 上验证（Windows 10/11 + Windows Terminal）。Linux / WSL 尚未适配，远程开发主链路不可用，详见[平台支持](#平台支持)。

## 项目介绍

远程开发的日常操作往往要在多条命令之间来回切换：查 `~/.ssh/config`、选主机、连上去、列 tmux 会话、附着或新建、推送公钥……ShellPrompt 把这些步骤收进终端里的交互界面：

- 运行 `sss`，从 SSH config 的主机列表中直接选择目标；
- 在 tmux 仪表盘里用方向键和单键完成附着、新建、刷新、删除和 SSH 直连；
- 用 `ssh-copy-id` 别名把本机公钥一键追加到新主机；
- 打开 PowerShell 时自动渲染欢迎 Banner，并初始化 Starship、fnm、PSReadLine。

它适合经常通过 SSH 连接多台开发机、用 tmux 维持远程会话的 Windows PowerShell 用户。

终端界面组件（Terminal.Gui v2）和进度动画组件（PwshSpectreConsole）**随仓库提供**，不需要单独安装。

## 功能展示

以下为界面结构的文本示意（不是截图），实际配色、列宽会随终端尺寸变化。

**SSH 主机仪表盘**（运行 `sss`）：

```text
ShellPrompt · SSH 主机                         上次: deb
 All  AWS  DigitalOcean  Local  Other
┌─ ● deb       ▸prod  #prod #web   2h   ┐ ┌ Connection ────────┐
│  ● web       ▸prod  #prod         刚刚  │ │ Host     deb       │
│  ● local                             3d │ │ Address  10.0.0.1  │
│  ● do1       ▸dev   #dev           —    │ │ Port     22        │
└────────────────────────────────────────┘ │ User     root      │
                                           │ Status   ● 在线    │
                                           └────────────────────┘
分类 All · 4 台
Enter 连接 │ / 搜索 │ Tab 切换区域 │ ↑↓ 选择主机 │ ←→ 切换分类 │ Esc 退出
```

顶部分类来自 ssh config 里**真实**的 `# @provider` 元数据（没写就归到 `Other`）；
左侧列表显示状态点 / 主机名 / 分组 / 标签 / 最后活跃；右侧详情分
Connection / Activity / Tags / Infrastructure 四张卡片，远端状态**异步**加载、
加载中与失败都有明确提示。输入 `/` 实时过滤主机；上次使用的主机会置顶并在标题带右侧显示。

**tmux 会话仪表盘**：

```text
ShellPrompt TMUX Manager · 主机 deb                              已连接
会话: 3 · Attached: 1 · Detached: 2
┌────┬──────────────────────────────┬──────────┬─────────┐
│No  │SESSION                       │  STATUS  │  WINDOWS│
├────┼──────────────────────────────┼──────────┼─────────┤
│1   │work-main                     │ Attached │        4│
│2   │feature-api                   │ Detached │        6│
│3   │scratch                       │ Detached │        1│
└────┴──────────────────────────────┴──────────┴─────────┘
Enter  附着 │ n  新建 │ r  刷新 │ s  SSH │ x  删除 │ q  退出 │ Esc  退出
```

| 按键 | 操作 |
|------|------|
| `↑` / `↓` | 选择会话 |
| `Enter` | 附着 / 恢复选中会话 |
| `n` | 新建 tmux 会话 |
| `r` | 刷新会话列表（连接失败时重试） |
| `s` | 直接 SSH 登录（失败时直连排查） |
| `x` | 删除选中会话（需要二次确认，默认 `n`） |
| `q` / `Esc` | 退出管理器 |

终端较窄时，`STATUS` / `WINDOWS` 列和底栏按钮会自动取舍；无会话和连接失败是两种明确区分的状态，不会用空表格冒充。

## 核心功能

| 功能 | 你能做什么 |
|------|------------|
| **SSH 主机管理** | 自动读取 `~/.ssh/config`，用 `sss` 交互选择主机；在当前会话内记住上次使用的主机并置顶（重启后可用配置预置 `SSH.LastHost`）；主机名会在连接前做白名单校验 |
| **tmux 会话管理** | 在一个仪表盘里查看远端会话、附着/恢复、新建、刷新、删除，或直接 SSH 登录；删除必须经过交互确认 |
| **交互式 TUI** | 全屏终端界面（Terminal.Gui v2），支持方向键、单键快捷键、搜索过滤和窗口缩放，无需额外安装 UI 依赖 |
| **终端体验增强** | 启动欢迎 Banner + 随机语录、PSReadLine 历史补全增强、Starship 提示符、fnm 自动切换 Node 版本 |
| **公钥部署** | `Copy-SshPublicKey` / `ssh-copy-id` 自动按 `ed25519 > ecdsa > rsa > dsa` 顺序查找公钥并推送到远端 `authorized_keys` |
| **天气** | SSH 主机仪表盘标题带显示 wttr.in 天气；`Update-Weather` 可手动绕过缓存刷新一次 |
| **配置管理** | 通过 `$HOME/.ShellPrompt/config.ps1` 覆盖颜色、路径、天气、SSH 记忆和 TUI 主题 |

## 系统要求与依赖

### 运行环境

- **Windows**（验证环境为 Windows 10/11 + Windows Terminal）
- **PowerShell 7.6+**（Windows PowerShell 5.1 不受支持，模块清单会直接拒绝加载）
- 远程开发另需：本机 **OpenSSH 客户端**（`ssh.exe`），以及远端主机上的 **tmux**

### 依赖一览

| 类别 | 组件 | 说明 |
|------|------|------|
| 必需 | PowerShell 7.6+ | 模块清单声明的最低版本；内置 UI 组件基于 .NET 10，需要 7.6+ |
| 必需（仓库内置） | PwshSpectreConsole 2.6.3 | 硬依赖，位于 `Modules/PwshSpectreConsole/2.6.3/`，导入模块时自动加载；目录缺失会导致模块导入失败 |
| 必需（仓库内置） | Terminal.Gui 2.4.10 | 交互式界面的渲染实现，位于 `Modules/Terminal.Gui/2.4.10/`；首次进入 `sss` 时加载。缺失时交互式命令会报明确错误，模块本身仍可导入 |
| 可选 | Starship | 提示符接管；通过 `Get-Command starship` 检测，未安装时保留 PowerShell 默认提示符 |
| 可选 | fnm | Node.js 版本管理；**仅按 `fnm.exe` 检测**，Linux / WSL 上会自动跳过 |
| 按需 | OpenSSH 客户端（`ssh.exe`） | SSH / tmux 管理、`ssh-copy-id` 需要；未安装时可通过 Windows「可选功能」添加，详见安装步骤 |
| 按需（远端） | tmux | 仪表盘管理的是**远端主机**上的 tmux 会话 |
| 可选 | curl | 天气查询优先使用系统 `curl.exe`，缺失时回退到 PowerShell 内置的 `Invoke-RestMethod` |
| 可选 | PSReadLine | PowerShell 7 自带；存在时启用历史补全和更顺手的按键绑定 |

> 表中两个「仓库内置」组件随仓库一起分发，**不需要** `Install-Module` 或另行下载。ShellPrompt **未发布到 PowerShell Gallery**，请按下方步骤从仓库导入。

### 平台支持

| 平台 | 状态 | 说明 |
|------|------|------|
| Windows 10/11 + Windows Terminal | ✅ 支持 | CI 在 `windows-latest` 上运行；tmux 仪表盘在 Windows Terminal + PowerShell 7.6.3 做过真机验收 |
| Windows + conhost | ⚠️ 未单独验证 | 建议使用 Windows Terminal |
| Linux | ❌ 远程开发主链路不可用 | 欢迎 Banner 和模块导入可以工作，Starship / 天气（`Invoke-RestMethod` 回退）未做完整验证；SSH / tmux / fnm / `ssh-copy-id` 依赖 `ssh.exe`、`~/.ssh\config`、`$env:USERPROFILE`、`$env:LOCALAPPDATA` 等 Windows 专有假设 |
| WSL | ❌ 未适配 | 情况同 Linux；即使通过 Windows interop 调用了 `ssh.exe`，使用的也是 Windows 侧配置与密钥，未做验证 |
| Windows PowerShell 5.1 | ❌ 不支持 | 模块清单要求 PowerShell 7.6+ |

## 安装

### 1. 准备 PowerShell 7.6+

```powershell
winget install --id Microsoft.PowerShell --source winget
```

安装后重新打开终端，确认版本：

```powershell
$PSVersionTable.PSVersion   # 应为 7.6 或更高
```

需要远程开发时，再确认 OpenSSH 客户端可用：

```powershell
Get-Command ssh.exe
```

Windows 10/11 可通过「设置 → 应用 → 可选功能」添加「OpenSSH 客户端」。远端主机需要自行安装 tmux（例如 Debian / Ubuntu 上执行 `sudo apt install tmux`）。

### 2. 克隆仓库

```powershell
git clone https://github.com/arbaleast/PowerShell.git "$HOME\PowerShell"
```

也可以克隆到任意目录，后续步骤中的路径按实际位置替换即可。

### 3. 让 `$PROFILE` 加载仓库内的 profile

仓库根目录的 `Microsoft.PowerShell_profile.ps1` 以**自身所在目录**为仓库根来定位 `ShellPrompt/` 模块与 `Modules/` 依赖，因此不要把它复制到 `$PROFILE` 位置，而是在 `$PROFILE` 里引用它：

```powershell
# 确保 $PROFILE 所在目录存在
New-Item -ItemType Directory -Force -Path (Split-Path $PROFILE) | Out-Null

# 在 $PROFILE 末尾追加一行 dot-source（路径按实际克隆位置修改）
Add-Content $PROFILE '. "$HOME\PowerShell\Microsoft.PowerShell_profile.ps1"'
```

之后每次启动 PowerShell 都会加载仓库内的 profile；更新仓库时执行 `git pull` 即可，无需重新复制文件。

### 4. 验证安装

新开一个 PowerShell 窗口，应看到欢迎 Banner 与随机语录，然后：

```powershell
Get-Alias sss          # sss -> Start-TmuxSession
Get-Command sss        # 确认命令存在
```

首次运行 `sss`（或 `ssh-copy-id`）时才会完成 ShellPrompt 模块初始化，因此第一次调用可能比后续调用稍慢。

### 手动导入（调试用）

只想加载模块、不修改 `$PROFILE` 时：

```powershell
Import-Module "$HOME\PowerShell\ShellPrompt\ShellPrompt.psd1"
Get-Command -Module ShellPrompt
```

> 手动导入只暴露模块的 5 个公开命令，不会注册 `ll` / `which` / `sss` / `ssh-copy-id` 这些 profile 别名。

## 快速开始

在已配置好 `$PROFILE` 的交互式 PowerShell 中：

```powershell
# 1. 打开 SSH 主机仪表盘，选择主机后进入 tmux 仪表盘
sss

# 2. 跳过选择器，直接管理指定主机（主机名来自 ~/.ssh/config）
sss deb

# 3. 把本机默认公钥推送到远程主机
ssh-copy-id user@example.com

# 4. 手动刷新一次天气（绕过 10 分钟缓存）
Update-Weather

# 5. 修改模块源码或 ~/.ShellPrompt/config.ps1 后重载配置
Invoke-Reload
```

说明：

- 第 2 步中的 `deb` 是位置参数，等价于 `Start-TmuxSession deb`；示例统一使用位置参数，首次调用时最稳妥。
- `Update-Weather` 和 `Invoke-Reload` 需要 ShellPrompt 模块已加载；如果新会话里提示命令不存在，先运行一次 `sss`（或手动 `Import-Module`）。
- `ssh-copy-id` 是 `Copy-SshPublicKey` 的别名；公钥默认按 `ed25519 > ecdsa > rsa > dsa` 顺序查找。

## 配置

用户配置文件：

```powershell
$HOME/.ShellPrompt/config.ps1
```

文件默认不存在，需要时自行创建。用户配置覆盖模块内置默认值（**用户配置 → 默认配置**），完整配置项与示例见 [配置说明](docs/readme/configuration.md)。

```powershell
# ~/.ShellPrompt/config.ps1
# 注意：PowerShell 双引号字符串不解析 \e，用反引号转义 `e
$Config.Colors.FreshGreen = "`e[38;2;0;255;0m"   # 覆盖主色调
$Config.Weather.Enabled   = $false                # 关闭 SSH 主机仪表盘标题带天气
$Config.SSH.LastHost      = 'my-server'           # 预置置顶主机
```

修改后运行 `Invoke-Reload` 生效。

> 配置文件会被启动流程和模块各加载一次，因此只应做 `$Config.*` 赋值，不要在文件里调用模块内部函数或设置别名。

## 文档导航

| 你想了解 | 阅读 |
|----------|------|
| 安装与上手 | 本 README 的「安装」「快速开始」 |
| 有哪些功能、界面怎么操作 | [功能特点](docs/readme/features.md) |
| 公开命令、参数、别名 | [命令一览](docs/readme/commands.md) |
| 配置文件位置与全部配置项 | [配置说明](docs/readme/configuration.md) |
| TUI 仪表盘的结构、键位与终端行为 | [TUI 仪表盘](docs/readme/tui-dashboard.md) |
| 模块目录结构、加载流程、渲染分工 | [架构说明](docs/readme/architecture.md) |
| 参与开发、跑测试与静态分析 | [开发者指南](docs/readme/development.md)、[`AGENTS.md`](AGENTS.md) |

## 故障排除

| 症状 | 可能原因 | 解决方案 |
|------|----------|----------|
| `sss` 提示找不到 `ShellPrompt` 模块 | profile 被**复制**到 `$PROFILE`，仓库根定位失效 | 删除复制过去的内容，改为在 `$PROFILE` 中 dot-source 仓库内的原文件 |
| `sss` 提示 "SSH 配置中未找到任何主机" | `~/.ssh/config` 不存在或没有 `Host` 条目 | 在 `~/.ssh/config` 中添加主机配置 |
| `sss` 提示 "当前不是交互式终端" | 在管道、重定向或 CI 中调用了交互式命令 | 在真实终端中运行 |
| `无法执行 ssh: ...` | 未安装 OpenSSH 客户端，或 `ssh.exe` 不在 PATH | 安装 Windows 的 OpenSSH 客户端，或把 `ssh.exe` 加入 PATH |
| 远端主机提示没有 tmux | 远端未安装 tmux | 在远端安装 tmux，或用 `s` 直连 SSH 后手动处理 |
| 主机名包含非法字符 | 输入含空格、斜杠等特殊字符 | 主机名仅允许字母、数字、`.`、`-`、`_` |
| `Copy-SshPublicKey` 提示找不到默认公钥 | 本机未生成 SSH 密钥对 | 执行 `ssh-keygen -t ed25519` 生成密钥 |
| `Update-Weather` / `Invoke-Reload` 提示不是命令 | ShellPrompt 模块尚未加载 | 先运行一次 `sss`，或手动 `Import-Module` |
| 天气一直不显示 | 网络不可达、wttr.in 限流，或 `Weather.Enabled = $false` | 检查网络与配置；可用 `Update-Weather` 手动测试 |
| Starship / fnm 没有生效 | 工具未安装或不在 PATH | 用 `Get-Command starship` / `Get-Command fnm` 检查；fnm 仅在 Windows 生效 |
| PSReadLine 不可用 | PSReadLine 未安装 | 执行 `Install-Module PSReadLine -Force` |
| 删除 tmux 会话 | — | 删除必须在仪表盘里显式选中会话，并经过默认答案为 `n` 的二次确认 |

## 开发与贡献

- 架构与加载流程：[架构说明](docs/readme/architecture.md)
- 命名、作用域、错误处理、测试与提交规范：[开发者指南](docs/readme/development.md)（权威版本在 [`docs/agents/`](docs/agents/)）
- 测试与静态分析统一入口：

  ```powershell
  pwsh -NoProfile -File ./ShellPrompt/Tests/Invoke-Tests.ps1
  pwsh -NoProfile -File ./ShellPrompt/Tests/Invoke-Lint.ps1
  pwsh -NoProfile -File ./ShellPrompt/Tests/Invoke-ProfileSmoke.ps1
  ```

CI（`.github/workflows/test.yml`）在 `windows-latest` 上运行上述三道门禁。

## License

本项目基于 MIT 协议开源，详见 [`LICENSE`](ShellPrompt/LICENSE)。
