# ✨ 功能特点

## 远程开发体验

- **`Start-TmuxSession`** — 交互式菜单管理远程 tmux 会话。[`Start-TmuxSession.ps1`](../../ShellPrompt/Public/Start-TmuxSession.ps1)
- **`Copy-SshPublicKey`** — 一键推送 SSH 公钥到远程主机。[`Copy-SshPublicKey.ps1`](../../ShellPrompt/Public/Copy-SshPublicKey.ps1)
- **SSH Config 自动补全** — 自动解析 `~/.ssh/config` 主机列表，支持主机名 Tab 补全。[`Get-SshConfigHosts.ps1`](../../ShellPrompt/Private/Get-SshConfigHosts.ps1)

## 终端体验增强

- **ANSI 欢迎 Banner + 随机语录** — 启动时展示多彩 ASCII 横幅与随机语录。[`Show-UserScoopLogo.ps1`](../../ShellPrompt/Public/Show-UserScoopLogo.ps1)、[`quotes.txt`](../../data/quotes.txt)
- **PSReadLine 增强** — 基于历史记录的自动补全与优化导航体验。
- **Profile 加载计时** — 输出各阶段初始化耗时，便于调优。

## 交互式 UI 组件 (P2 阶段)

- **加载动画 (Spectre 单轨)** — 5 套样式名 (Braille / Ascii / Blocks / Dots / Arrows) 经 `Get-SpinnerStyleMapping` 翻译成 Spectre.Console 的 `Spinner.Known` 成员名, 由 `Invoke-WithProgress` 交给 `Invoke-SpectreCommandWithStatus` 渲染。自绘 spinner (`Show-ProgressSpinner`) 已于 2026-10-29 删除(无生产调用方)。[`Get-SpinnerStyleMapping.ps1`](../../ShellPrompt/Private/Get-SpinnerStyleMapping.ps1)
- **`Invoke-WithProgress` 封装** — 接受 `-ScriptBlock`，执行期间显示 Spectre 动画，异常统一重拋；集成于 `Start-TmuxSession` 入口的 SSH 探测与远程会话刷新。([`Invoke-WithProgress.ps1`](../../ShellPrompt/Private/Invoke-WithProgress.ps1))
- **欢迎 Banner 纯函数** — `New-WelcomeBanner` 构造行数组，`Get-RandomQuote` 带 mtime 缓存避免反复读盘；`Start-TmuxSession` 入口处展示运行主题 banner（主机名+语录）。([`New-WelcomeBanner.ps1`](../../ShellPrompt/Private/New-WelcomeBanner.ps1))
- **交互菜单 (GridView 单轨)** — 主机选择 / 会话管理 / tmux 会话列表三个菜单统一走 PSTui `Out-ConsoleGridView` 主轨，表格行、列裁剪与选中结果归一化由 GridView 私有函数负责。([`Invoke-GridViewMenu.ps1`](../../ShellPrompt/Private/Invoke-GridViewMenu.ps1))
- **会话状态文案** — 「● 已附着 / ○ 已分离」等状态文案由单一事实来源函数产出，菜单各入口不再各写一份。([`Get-TmuxSessionStateText.ps1`](../../ShellPrompt/Private/Get-TmuxSessionStateText.ps1))
- **GridView 配色** — 语义色键统一经 `Resolve-ColorTable` 解析（调用方覆盖 → 配置层默认值），并初始化为 Terminal.Gui `Scheme` 槽位。([`Resolve-ColorTable.ps1`](../../ShellPrompt/Private/Resolve-ColorTable.ps1))

## 现代工具链集成

- **Starship Prompt** — 跨 Shell 提示符，显示 git 上下文、Node 版本等信息。
- **Fnm (Node.js) 自动切换** — 进入项目目录时自动切换对应 Node 版本。
- **wttr.in 交互菜单标题区天气** — 三个交互菜单 (SSH 主机选择器 / tmux 管理器 / tmux 会话列表) 的 PSTui 窗口**标题区**自动追加一行 wttr 天气短串 (如 `Shanghai: 🌫 +18°C`), 顶部居中显示. 复用 [`Get-WttrWeather`](../../ShellPrompt/Private/Get-WttrWeather.ps1) 10 分钟缓存 + 5 秒超时 + 错误兜底. 详见下方 [交互菜单标题区天气](#-交互菜单标题区天气) 章节.

## 工作流便利

- **`Invoke-Reload`** — 一键重载 PowerShell Profile。[`Invoke-Reload.ps1`](../../ShellPrompt/Public/Invoke-Reload.ps1)
- **全局别名** — `ll` (Get-ChildItem)、`which` (where.exe)、`sss` (Start-TmuxSession)、`ssh-copy-id` (Copy-SshPublicKey)。

## 🌤️ 交互菜单标题区天气

三个交互菜单 (SSH 主机选择器 / tmux 管理器 / tmux 会话列表) 的 PSTui **窗口标题区**自动追加一行 wttr 天气短串 —— 由独立私有函数 [`Get-WttrTitleSuffix.ps1`](../../ShellPrompt/Private/Get-WttrTitleSuffix.ps1) 在 [`Invoke-GridViewMenu.ps1`](../../ShellPrompt/Private/Invoke-GridViewMenu.ps1) 的三个菜单调用点 (`Invoke-GridViewHostSelector` / `Invoke-GridViewSessionManager` / `Invoke-GridViewSessionList`) 拼装 `-Title` 参数之前判定 `$script:Config.Weather.Enabled`; 启用时调 `Get-WttrWeather -Format CustomUrl -Url 'https://wttr.in/?format=j1&lang=zh' -CacheMinutes 10` (复用 10 分钟缓存), 自解析 j1 拿到 `nearest_area[0].areaName[0].value` (城市名) + `current_condition[0].temp_C` (温度) + `current_condition[0].weatherDesc[0].value` (天气描述), 自拼成 ` - <City>: <Desc> <Temp>°C` 片段附加到标题末尾. 失败/超时/禁用时静默跳过, 绝不抛异常, 绝不污染主菜单.

> 提示行草案 A.2 于 2026-10-19 撤回, 仓库内的 `Write-GridViewHint` 函数随之于 2026-10-29 删除; 天气完全交给 PSTui 标题区做, 不会出现重复渲染.

> 端点选 `?format=j1` 而非 `?format=3`: 短格式在 IP 定位下会回退到 `lat,lon: 图标 温度`, 丢城市名 (wttr.in 对 nearest_area 的渲染策略不稳定). j1 一次性返回 nearest_area + current_condition, 我们自拼字符串, 行为完全可预测. 端点选择动机的完整论证见 [`Get-WttrTitleSuffix.ps1`](../../ShellPrompt/Private/Get-WttrTitleSuffix.ps1) 文件头注释与 [`docs/agents/wttr.md`](../agents/wttr.md) (CHANGELOG 已冻结, 相关条目不在其中).

> 天气描述已中文化 (客户端字典); 城市名跟随 wttr.in `nearest_area` 服务 (可能仍为英文拼音, IP 定位命中 `Chiuhuahsien` 这种). 中文化靠内置字典 (`Get-WttrWeatherDescMap`, 2026-10-29 核对共 42 条, 覆盖 `Smoky haze` / `Mist` / `Haze` / `Sunny` / `Cloudy` / `Partly Cloudy` / `Clear` / `Overcast` / 各种 Rain/Snow/Thunder 等), 未命中回退英文并 `Write-Verbose` 提示; 用户可在 `Weather.ExtraWeatherDescMap` 追加/覆盖条目.

**典型输出** (`sss` 主机选择菜单窗口标题区):

```text
SSH 主机选择器 (3) - Chiuhuahsien: 烟雾 26°C
```

**典型输出** (`sss` → tmux 管理器窗口标题区):

```text
TMUX 管理器 [debian] - tmux 3.5a - 会话 2 (附 1 / 分 1) - Chiuhuahsien: 烟雾 26°C
```

### 配置项（`$HOME/.ShellPrompt/config.ps1`）

`Weather` 配置域定义在 [`Initialize-Config.ps1`](../../ShellPrompt/Private/Initialize-Config.ps1):

| 键 | 类型 | 默认值 | 说明 |
|----|------|--------|------|
| `Weather.Enabled` | `bool` | `$true` | 总开关; `$false` 时 3 个菜单标题区均不追加 wttr 片段 |
| `Weather.ExtraWeatherDescMap` | `[ordered]@{}` | `{}` | 用户自定义 wttr.in `weatherDesc` 英文 → 中文映射; 键 = 英文短语 (匹配时 `.ToLower()`), 值 = 中文; 同名键覆盖内置字典 |

```powershell
# ~/.ShellPrompt/config.ps1
$Config.Weather.Enabled = $false                                          # 禁用交互菜单标题区天气

# 追加/覆盖 wttr 描述中文 (同名键覆盖内置字典)
$Config.Weather.ExtraWeatherDescMap = [ordered]@{
    'smoky haze' = '烟霞'                                                  # 覆盖内置 'Smoky haze' → '烟雾'
    'my custom desc' = '自定义描述'                                        # 用户自创的本地化条目
}
```

### 公开命令 `Update-Weather`

[`Update-Weather`](../../ShellPrompt/Public/Update-Weather.ps1) **绕过缓存**强制拉取一次 wttr 短格式（`?format=3`，`-CacheMinutes 0`）并立即 `Write-Host` 渲染 —— 适用于手动验证 wttr.in 是否可达、或在终端里临时拉一次最新天气:

```powershell
PS> Update-Weather
Shanghai: 🌫 +18°C
```

任何时候都可直接调用, 不影响交互菜单标题区的渲染流程 (调用方不感知).

> 注：`Update-Weather` 与菜单标题区走两条不同 HTTP 路径（短格式 `?format=3` vs j1 自拼 `?format=j1&lang=zh`），缓存**键**不同互不命中（`Short|...` vs `CustomUrl|...`）；但模块内缓存是**单槽**结构，一方成功抓取会**挤掉**另一方的缓存条目，之后再开菜单/再调用会重新拉取。菜单标题区走 `Get-WttrTitleSuffix` 内置中文字典翻译。

### 降级场景

| 场景 | 行为 |
|------|------|
| `Weather.Enabled = $false` | 标题区不追加 wttr 片段 (只渲染原标题) |
| wttr.in 超时 / 网络失败 / 远端空响应 | 静默返回空串; 主菜单标题渲染不受影响 |
| 模块作用域 wttr 缓存 (`$script:_WttrCache`) 命中 | 零 HTTP; 二次开菜单直接命中 |

> `Get-WttrWeather` 的容错语义统一收敛在该函数里: HTTP 失败一律返回 `""` + `Write-Verbose` 诊断, **绝不抛异常污染菜单**.

---

## 🌤️ 提示符天气

本项目**不接管** `Function:prompt`，prompt 渲染由 starship 接管。

`Get-WttrWeather` 保留为**模块私有**函数（未导出，直接调用会报“无法识别”）。如需在自己的 prompt / 脚本中复用，进入模块作用域调用：

```powershell
# 在自己的 profile 中示例: 拉一次短格式天气 (绕过缓存)
& (Get-Module ShellPrompt) { Get-WttrWeather -Format Short -CacheMinutes 0 }
```

公开命令 `Update-Weather` 用于手动刷新并打印 wttr 短串，是最简单的用户入口。

