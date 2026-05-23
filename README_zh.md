```
____  ____  ____  ____   ___  _____ ___ _     _____
|  _ \/ ___||  _ \|  _ \/ _ \|  ___|_ _| |   | ____|
| |_) \___ \| |_) | |_) | | | | |_   | || |   |  _|
|  __/ ___) |  __/|  _ <| |_| |  _|  | || |___| |___
|_|   |____/|_|   |_| \_\\___/|_|   |___|_____|_____|
```

### ⌨️ SSH + tmux 会话管理器 (PowerShell)

> 通过交互式菜单管理远程 tmux 会话。`sss <host>` 即可附加、创建或切换会话。
> 配合 Starship 提示符、Fnm Node 版本切换、PSReadLine 让终端更好用。

[![MIT License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-blue.svg)](https://github.com/PowerShell/PowerShell)
[![Starship](https://img.shields.io/badge/Starship-Prompt-8356ff.svg)](https://starship.rs)
[![Tmux](https://img.shields.io/badge/Tmux-Sessions-1BB91F.svg)](https://github.com/tmux/tmux)

[English Version](./README.md) · [报告问题](https://github.com/arbaleast/PowerShell/issues) · [功能建议](https://github.com/arbaleast/PowerShell/issues)

---

## 📸 截图

**启动语录:**

```
  ┌──〈 arbaleast@G7 〉━━[ PowerShell ]━━[ SHELL PROMPT ]
  │
  │  ┄
  │  DONE  代码是写给人看的，顺便给机器运行。
  │  2026-05-23 07:34:17
  │
  │  ┄
  └───────────────────────────────────────────── ○
```

**Tmux 管理器 (`sss <host>`):**

```
  +--< arbaleast@G7 >--[ PowerShell ]--[ REMOTE TMUX | myhost ]
  |
  |  +
  |    [01] RESUME
  |    [02] ATTACH
  |  > [03] NEW
  |    [04] LIST
  |    [05] KILL
  |    [06] EXIT
  |
  |  +
  |  -- create a new named session

  up/down navigate + Enter confirm + Q quit
```

**新建会话输入：**

```
  session name (Enter = random):
```

---

## ✨ 功能特点

### 🚀 性能

- **懒加载** — tmux 模块仅在你首次输入 `sss` 时才加载
- **快速启动** — 最小化足迹，毫秒级加载

### 🛠️ 开发者工具

- **Starship 提示符** — 跨 Shell 提示符，显示 git 上下文、Node 版本
- **Fnm 集成** — cd 切换项目时自动切换 Node 版本
- **PSReadLine** — 基于历史的自动补全，更好的导航体验

### 🔧 远程会话

- **Tmux 管理器** — 交互式菜单管理远程 tmux 会话
- **快速连接** — `sss <host>` 立即附加/恢复/创建会话
- **SSH 回退** — 远程主机无 tmux 时，自动回退到普通 SSH 登录

### 💧 喝水提醒

- **智能提醒** — Windows Toast 通知，每 ~60 分钟根据时段(早/午/晚)发送不同文案
- **天气感知** — 通过 wttr.in 获取当前温度，自动缩短高温时段间隔、延长低温时段
- **每日目标** — 2000ml 目标追踪，可视化历史记录查看，支持 `Get-WaterReminderHistory` 及其别名 `Get-WaterHistory`
- **夜间免打扰** — 22:00-07:00 自动进入休眠模式，不推送通知
- **后台运行** — `water -Background` 在后台静默运行，不占用终端
- **零依赖** — 依赖 Windows 原生通知 API，优先使用 Toast，支持 WinForms / msg.exe 回退，无需额外 PowerShell 模块

### 🎇 后台服务指南（若启用喝水提醒）

- 启动后台运行：`water -Background`
- 停止后台运行：`water -Stop`
- 查看状态：`water -Status`
- 如果 `water -Background` 启动后未出现通知，请查看 `data/water-reminder.log`，确认通知回退或者天气获取是否异常。
- 提示会优先使用 Windows 原生 Toast；若系统不支持，将回退到 WinForms 通知或 `msg.exe`。

### �📁 日常优化

- **快捷别名** — `ll`、`..`、`~`、`which` 加速导航
- **模块化结构** — 自包含 `ShellPrompt/` 模块，单一入口，易于维护

---

## 📂 目录结构

```
PowerShell/
│
├── Microsoft.PowerShell_profile.ps1   # 🎯 极简入口 — 导入模块
├── quotes.txt                         # 💬 随机启动语录
├── data/
│   ├── quotes.txt                     # 💬 随机启动语录
│   └── water-history.json             # 💧 每日喝水记录（若启用喝水提醒）
├── README.md / README_zh.md
└── ShellPrompt/                      # 📦 自包含模块
    ├── ShellPrompt.psd1              # 📋 模块清单
    ├── ShellPrompt.psm1               # 🚪 入口（配置 → Private → Public → 导出）
    ├── Private/
    │   ├── Initialize-Config.ps1      # ⚙️  全局配置（$UserScoop_CONF）
    │   ├── Invoke-ConsoleMenu.ps1       # 🖼️  通用 UI 菜单（无 tmux 知识）
    │   ├── Get-TmuxSessions.ps1         # 🔌 SSH → tmux ls 解析器
    │   ├── Invoke-SessionSelector.ps1   # 🔀 会话选择子菜单
    │   ├── Invoke-WaterReminder.ps1     # 💧 核心提醒逻辑（天气、间隔、日志）
    │   └── Send-WaterNotification.ps1   # 🔔 Windows Toast 通知发送
    └── Public/
        ├── Initialize-Environment.ps1  # 🛠️  Starship / Fnm / PSReadLine + logo
        ├── Show-UserScoopLogo.ps1       # 🎨 启动语录渲染
        ├── Invoke-Reload.ps1            # 🔄 reload 命令
        ├── Set-ProfileAliases.ps1        # 🔗 ll, .., ~, which
        ├── Start-TmuxSession.ps1        # 🚀 Tmux 会话管理器（导出）
        └── Start-WaterReminder.ps1      # 💧 喝水提醒入口（导出）
```

### 模块架构

`ShellPrompt.psm1` 按严格顺序加载：

1. **Private/Initialize-Config.ps1** — 初始化 `$global:UserScoop_CONF`（颜色、按键、SSH/Tmux 配置、语录路径、喝水提醒配置）
2. **Private/** — 内部辅助函数（Invoke-ConsoleMenu、Get-TmuxSessions、Invoke-SessionSelector、Invoke-WaterReminder、Send-WaterNotification）
3. **Public/** — 用户可见命令（Initialize-Environment、Show-UserScoopLogo、Start-TmuxSession、Start-WaterReminder、Get-WaterReminderHistory、reload）
4. **Export-ModuleMember** — 仅导出 Public/*.ps1 中的函数；Private 对外部不可见

这确保了 MVC 边界：UI 逻辑（`Invoke-ConsoleMenu`）对 tmux 和 SSH 一无所知，通知发送（`Send-WaterNotification`）与提醒调度逻辑解耦。

---

## 🚀 快速开始

### 1️⃣ 安装依赖

请确保系统已安装以下工具：

| 工具 | 用途 | 安装指南 |
|------|------|----------|
| [Starship](https://starship.rs/) | 美观提示符，带 git 上下文 | [安装](https://starship.rs/guide/#🚀-installation) |
| [Fnm](https://github.com/Schniz/fnm) | 快速 Node 版本管理器 | [安装](https://github.com/Schniz/fnm#installation) |
| [OpenSSH](https://docs.microsoft.com/windows-server/administration/openssh/openssh_install_firstuse) | 远程 SSH 客户端 | Windows 10/11 内置或安装 OpenSSH |
| [tmux](https://github.com/tmux/tmux) | 远程会话保持 | [安装](https://github.com/tmux/tmux/wiki/Installing) |
| Windows 通知支持 | Windows 原生 Toast / WinForms / msg.exe 回退 | 现代 Windows 已内置，旧版可使用 msg.exe |

### 2️⃣ 安装

```powershell
# 查看 PowerShell 配置目录
$PROFILE

# 将仓库克隆到永久目录
git clone https://github.com/arbaleast/PowerShell.git D:\path\to\PowerShell

# 在配置目录创建一个桩文件，加载真实模块
"`$PROFILE_DIR = 'D:\path\to\PowerShell'" | Out-File -Encoding UTF8 "`$PROFILE" -NoClobber
"`. `$PROFILE_DIR\Microsoft.PowerShell_profile.ps1" | Add-Content "`$PROFILE"

# 重启 PowerShell 或执行：
reload
```

> `quotes.txt` 位于仓库根目录，模块加载时自动找到。

### 3️⃣ 自定义配置（可选）

编辑 `ShellPrompt/Private/Initialize-Config.ps1` 自定义颜色、按键码、SSH 超时或默认会话名。

---

## ⚡ 命令一览

| 命令 | 说明 |
|------|------|
| `sss <host>` | 🖥️ 打开 tmux 管理器 → 连接远程主机 |
| `water` | 💧 启动喝水提醒（前台交互模式，倒计时显示） |
| `water -Background` | 💧 启动喝水提醒（后台静默运行） |
| `water -Stop` | 💧 停止后台喝水提醒 |
| `water -Status` | 💧 查看今日饮水进度 |
| `Get-WaterReminderHistory` | 💧 查看最近喝水历史（默认最近 7 天） |
| `Get-WaterHistory` | 💧 `Get-WaterReminderHistory` 的别名 |
| `reload` | 🔄 重载 PowerShell 配置 |
| `ll` | 📋 详细列出文件 |
| `..` | ⬆️ 跳转到父目录 |
| `~` | 🏠 跳转到主目录 |
| `which <cmd>` | 🔍 查找命令所在位置 |

---

## 🎨 配置说明

编辑 `ShellPrompt/Private/Initialize-Config.ps1` 自定义设置：

## 📜 开源协议

MIT © arbaleast

---

> 💡 **提示：** 如果觉得有用，别忘了 star ⭐
