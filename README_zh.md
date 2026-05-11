```
____  ____  ____  ____   ___  _____ ___ _     _____
|  _ \/ ___||  _ \|  _ \/ _ \|  ___|_ _| |   | ____|
| |_) \___ \| |_) | |_) | | | | |_   | || |   |  _|
|  __/ ___) |  __/|  _ <| |_| |  _|  | || |___| |___
|_|   |____/|_|   |_| \_\\___/|_|   |___|_____|_____|
```

### ⌨️ 模块化 PowerShell 配置，支持 tmux 会话管理、Starship 提示符和跨平台工具

[![MIT License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-blue.svg)](https://github.com/PowerShell/PowerShell)
[![Starship](https://img.shields.io/badge/Starship-Prompt-8356ff.svg)](https://starship.rs)
[![Tmux](https://img.shields.io/badge/Tmux-Sessions-1BB91F.svg)](https://github.com/tmux/tmux)

[English Version](./README.md) · [报告问题](https://github.com/arbaleast/PowerShell/issues) · [功能建议](https://github.com/arbaleast/PowerShell/issues)

---

## 📸 截图

```
  * ACTIVE -- 14:32

    💬 代码是写给人看的，顺便给机器运行。

  ----------------------------------------------
  
  ~/Projects/PowerShell on main偏
  ❯ _
```

**Tmux 管理器 (`sss <host>`):**

```
┌─────────────────────────────────────────┐
│         REMOTE TMUX SESSION             │
├─────────────────────────────────────────┤
│  ▶  RESUME  — 附加到 'main'             │
│     ATTACH  — 仅附加到现有会话          │
│     NEW     — 创建新会话                │
│     LIST   — 查看所有会话              │
│     KILL   — 终止所有 tmux            │
│  ▶  [q] EXIT  — 返回本地终端             │
└─────────────────────────────────────────┘
        ↑↓ 移动  ·  Enter 确认  ·  q 退出
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

### 📁 日常优化
- **快捷别名** — `ll`、`..`、`~`、`which` 加速导航
- **模块化结构** — 易于定制，易于维护

---

## 📂 目录结构

```
PowerShell/
│
├── Microsoft.PowerShell_profile.ps1   # 🎯 极简入口 — 导入模块
├── quotes.txt                         # 💬 随机启动语录
├── README.md / README_zh.md
└── ShellPrompt/                      # 📦 自包含模块
    ├── ShellPrompt.psd1              # 📋 模块清单
    ├── ShellPrompt.psm1               # 🚪 入口（配置 → Private → Public → 导出）
    ├── Private/
    │   ├── Initialize-Config.ps1      # ⚙️  全局配置（$UserScoop_CONF）
    │   ├── Invoke-ConsoleMenu.ps1       # 🖼️  通用 UI 菜单（无 tmux 知识）
    │   ├── Get-TmuxSessions.ps1         # 🔌 SSH → tmux ls 解析器
    │   └── Invoke-SessionSelector.ps1   # 🔀 会话选择子菜单
    └── Public/
        ├── Initialize-Environment.ps1  # 🛠️  Starship / Fnm / PSReadLine 初始化
        ├── Show-UserScoopLogo.ps1       # 🎨 启动语录渲染
        ├── Invoke-Reload.ps1            # 🔄 reload 命令
        ├── Set-ProfileAliases.ps1        # 🔗 ll, .., ~, which
        └── Start-TmuxSession.ps1        # 🚀 主入口（导出）
```

### 模块架构

`ShellPrompt.psm1` 按严格顺序加载：

1. **Private/Initialize-Config.ps1** — 初始化 `$global:UserScoop_CONF`（颜色、按键、SSH/Tmux 配置）
2. **Private/** — 内部辅助函数（Invoke-ConsoleMenu、Get-TmuxSessions 等）
3. **Public/** — 用户可见命令（Initialize-Environment、Start-TmuxSession、reload 等）
4. **Export-ModuleMember** — 仅导出 Public/*.ps1 中的函数；Private 对外部不可见

这确保了 MVC 边界：UI 逻辑（`Invoke-ConsoleMenu`）对 tmux 和 SSH 一无所知。

---

## 🚀 快速开始

### 1️⃣ 安装依赖

请确保系统已安装以下工具：

| 工具 | 用途 | 安装指南 |
|------|------|----------|
| [Starship](https://starship.rs/) | 美观提示符，带 git 上下文 | [安装](https://starship.rs/guide/#🚀-installation) |
| [Fnm](https://github.com/Schniz/fnm) | 快速 Node 版本管理器 | [安装](https://github.com/Schniz/fnm#installation) |
| [tmux](https://github.com/tmux/tmux) | 远程会话保持 | [安装](https://github.com/tmux/tmux/wiki) |

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