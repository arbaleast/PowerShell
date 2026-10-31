# ✨ 功能特点

本页从使用者的角度说明 ShellPrompt 能做什么、交互界面怎么用。命令与参数见 [命令一览](commands.md)，配置项见 [配置说明](configuration.md)，TUI 的完整交互契约见 [TUI 仪表盘](tui-dashboard.md)。

## 🖥️ SSH 主机管理

- **主机来源**：自动读取 `~/.ssh/config` 中的 `Host` 别名（支持多模式行，只取第一个别名；含通配符或非法字符的条目会被忽略）。
- **交互式选择**：运行 `sss`（不接主机名）打开全屏主机选择器：

  ```text
  SSH 主机选择器 (3) - Chiuhuahsien: 烟雾 26°C
  搜索: _
  ┌──────────────────────┬──────────┐
  │HOST                  │STATE     │
  ├──────────────────────┼──────────┤
  │debian                │★ 最近    │
  │dev-box               │          │
  └──────────────────────┴──────────┘
  ↑↓ 选择 · Enter 确认 · Esc 取消 · Tab 切焦点
  ```

  - 标题行显示主机数量和（启用时）天气；
  - 在搜索框中输入文字即实时过滤主机列表；
  - 当前会话内上次使用过的主机会置顶并标注 `★ 最近`（重启后可在 `$Config.SSH.LastHost` 中预置）；
  - `↑` / `↓` 移动，`Enter` 确认，`Esc` 取消，`Tab` 在搜索框与主机表之间切换焦点。
- **直接指定主机**：`sss <主机名>` 跳过选择器，直接进入该主机的 tmux 仪表盘。
- **主机名补全**：模块为 `Start-TmuxSession` 的 `-HostName` 参数注册了来自 SSH config 的主机名补全（需要至少配置一台主机）。
- **连接前校验**：主机名只允许字母、数字、`.`、`-`、`_`，避免把特殊字符带进 SSH 命令行。

## 🧭 tmux 会话管理

选定主机后进入 tmux 仪表盘。界面分为标题带、会话统计、会话表和底部快捷键栏：

- **会话表**：列固定为 `#` / `SESSION` / `STATUS` / `WINDOWS`，选中行整行高亮；
- **状态区分**：正常有会话、远端没有会话（空态）、连接失败（错误态）是三种明确状态。空态和错误态不画空表格，而是显示居中指引；错误码只出现在状态行，不塞进会话表；
- **常用操作**：

  | 按键 | 操作 |
  |------|------|
  | `↑` / `↓` | 选择会话 |
  | `Enter` | 附着 / 恢复选中会话（无会话时不出现） |
  | `n` | 新建 tmux 会话 |
  | `r` | 刷新会话列表（错误态下显示为「重试」） |
  | `s` | 直接 SSH 登录（错误态下显示为「直连」） |
  | `x` | 删除选中会话（默认答案为 `n` 的二次确认） |
  | `q` / `Esc` | 退出管理器 |

- **删除安全**：删除操作必须先在表格里显式选中会话，再通过交互确认；确认过程出错或 SSH 失败都不会报告"删除成功"。
- **自适应**：窗口尺寸变化时界面自动重排；终端较窄时会隐藏次要列和部分快捷键提示，但按键语义不变。仪表盘最小按 40×10 布局，`STATUS` 列在宽度 ≥ 96 列时显示，`WINDOWS` 列在 ≥ 72 列时显示。
- **非交互环境护栏**：在管道、重定向或 CI 中调用时不会卡死，而是直接跳过交互界面并给出警告。

## 🔑 公钥部署

- `Copy-SshPublicKey`（别名 `ssh-copy-id`）把本机公钥追加到远端 `~/.ssh/authorized_keys`，模拟 Linux `ssh-copy-id` 的行为。
- 未指定 `-IdentityFile` 时，按 `id_ed25519.pub > id_ecdsa.pub > id_rsa.pub > id_dsa.pub` 的顺序在 `~/.ssh` 下查找默认公钥。
- 支持 `-Port` 指定 SSH 端口（默认 22）。
- 推送失败时以 ssh 退出码为准确认，不会静默报告成功。

```powershell
ssh-copy-id user@example.com
```

> 公钥自动探测与推送逻辑按 Windows 路径实现（使用 `$env:USERPROFILE` 和 `ssh.exe`），Linux / WSL 上不可用。

## ✨ 终端启动体验

- **欢迎 Banner + 随机语录**：每次启动 PowerShell 渲染带主机名、用户名、时间和随机语录的彩色 Banner；语录来自 `data/quotes.txt`，读取失败时回退到内置文案。
- **PSReadLine 增强**：存在 PSReadLine 时启用历史预测、Windows 编辑模式和 `Tab` 菜单补全。
- **Starship 提示符**：检测到 `starship` 时自动接管提示符；未安装时保留 PowerShell 默认提示符。
- **fnm 自动切换 Node**：检测到 `fnm.exe` 时初始化 fnm 环境，进入项目目录可自动切换 Node 版本。该能力目前只按 Windows 实现（`fnm.exe` + `$env:LOCALAPPDATA`），Linux / WSL 会自动跳过。

## 交互菜单标题区天气

SSH 主机选择器的标题行会追加一行 wttr.in 天气短串，例如：

```text
SSH 主机选择器 (3) - Chiuhuahsien: 烟雾 26°C
```

- 天气请求使用 10 分钟缓存和 5 秒超时；超时、网络失败或返回空内容时**静默跳过**，不影响主机选择器。
- 天气描述会翻译成中文，未命中的描述保留英文；城市名由 wttr.in 根据 IP 定位给出，可能与实际城市存在差异。
- 可通过配置关闭该功能或补充自定义翻译：

  ```powershell
  # ~/.ShellPrompt/config.ps1
  $Config.Weather.Enabled = $false

  $Config.Weather.ExtraWeatherDescMap = [ordered]@{
      'smoky haze'    = '烟霞'
      'my custom desc' = '自定义描述'
  }
  ```

### `Update-Weather`

`Update-Weather` 手动绕过缓存拉取一次 wttr.in 短格式天气并直接打印，适合验证网络可达性或临时查看最新天气：

```powershell
PS> Update-Weather
Shanghai: 🌫 +18°C
```

它不会改变主机选择器标题行的渲染流程；网络失败时给出提示而不是抛异常。

## 🎨 配置

所有可调行为都通过用户配置覆盖默认值：

```powershell
$HOME/.ShellPrompt/config.ps1
```

支持的配置域：`Paths`（语录路径）、`Colors`（ANSI 颜色）、`SSH`（上次使用的主机）、`Weather`（天气）、`UI`（TUI 主题）。完整键位、默认值与示例见 [配置说明](configuration.md)。
