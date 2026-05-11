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
├── Microsoft.PowerShell_profile.ps1   # 🎯 主入口 — 加载所有模块
├── ShellPrompt.psd1                   # 📦 模块清单
├── ShellPrompt.psm1                   # 📦 模块入口
├── Config.ps1                         # ⚙️  路径、颜色、键盘布局
├── Alias.ps1                          # 🔗 别名：ll, .., ~, reload, which
├── Utils.ps1                          # 🧰 辅助函数：logo, 终端初始化
├── Private/
│   ├── Invoke-ConsoleMenu.ps1         # 🖼️  通用 UI 菜单组件
│   ├── Get-TmuxSessions.ps1           # 🔌 SSH → tmux ls
│   ├── Get-TmuxMenuItems.ps1           # 📋 菜单状态构建器
│   └── Invoke-SessionSelector.ps1      # 🔀 会话选择子菜单
├── Public/
│   └── Start-TmuxSession.ps1           # 🚀 入口函数（导出）
└── quotes.txt                         # 💬 随机启动语录
```

### 模块架构

`ShellPrompt.psm1` 先加载 Private 函数（内部使用），再加载 Public 函数。仅 `Start-TmuxSession` 通过 `Export-ModuleMember` 导出，其余函数均为私有实现细节。

---

## 🚀 快速开始

### 1️⃣ 安装依赖

请确保系统已安装以下工具：

| 工具 | 用途 | 安装指南 |
|------|------|----------|
| [Starship](https://starship.rs/) | 美观提示符，带 git 上下文 | [安装](https://starship.rs/guide/#🚀-installation) |
| [Fnm](https://github.com/Schniz/fnm) | 快速 Node 版本管理器 | [安装](https://github.com/Schniz/fnm#installation) |
| [tmux](https://github.com/tmux/tmux) | 远程会话保持 | [安装](https://github.com/tmux/tmux/wiki) |

### 2️⃣ 安装配置文件

```powershell
# 步骤 A：查看 PowerShell 配置目录
$PROFILE

# 步骤 B：将仓库克隆到永久目录
git clone https://github.com/arbaleast/PowerShell.git D:\path\to\PowerShell

# 步骤 C：在配置目录创建一个桩文件，加载真实配置
# 将 "D:\path\to\PowerShell" 替换为实际克隆路径
"`$PROFILE_DIR = 'D:\path\to\PowerShell'" | Out-File -Encoding UTF8 "`$PROFILE" -NoClobber
"`. `$PROFILE_DIR\Microsoft.PowerShell_profile.ps1" | Add-Content "`$PROFILE"

# 步骤 D：重启 PowerShell 或执行：
reload
```

> 💡 **提示：** `quotes.txt` 会自动从脚本目录加载，无需额外配置。

### 3️⃣ 自定义配置（可选）

编辑 `Config.ps1` 自定义设置：

```powershell
# 默认路径（自动从脚本位置检测）
$global:UserScoop_ROOT = $PSScriptRoot  # quotes.txt 所在目录
$global:UserScoop_APPS = "...\apps"     # 工具安装目录
```

颜色方案和键盘码配置见下方 [配置说明](#-配置说明)。

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

编辑 `Config.ps1` 自定义设置：

## 📜 开源协议

MIT © arbaleast

---

> 💡 **提示：** 如果觉得有用，别忘了 star ⭐