# ⚡ PowerShell 配置

### ⌨️ 模块化 PowerShell 配置，支持 tmux 会话管理、Starship 提示符和跨平台工具

[![MIT License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-blue.svg)](https://github.com/PowerShell/PowerShell)
[![Starship](https://img.shields.io/badge/Starship-Prompt-8356ff.svg)](https://starship.rs)
[![Tmux](https://img.shields.io/badge/Tmux-Sessions-1BB91F.svg)](https://github.com/tmux/tmux)

[English Version](./README.md) · [报告问题](https://github.com/arbaleast/PowerShell/issues) · [功能建议](https://github.com/arbaleast/PowerShell/issues)

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
├── Config.ps1                       # ⚙️  路径、颜色、键盘布局
├── Alias.ps1                        # 🔗 别名：ll, .., ~, reload, which
├── Utils.ps1                        # 🧰 辅助函数：logo, 缓存, 导入
└── Remote.ps1                       # 🖥️  Tmux 会话管理器（懒加载）
```

---

## 🚀 快速开始

### 1️⃣ 安装

```powershell
# 查看配置路径
$PROFILE

# 复制文件（调整源路径）
Copy-Item -Path "D:\path\to\PowerShell\*.ps1" -Destination (Split-Path $PROFILE -Parent)
```

### 2️⃣ 依赖工具

| 工具 | 用途 | 一键安装 |
|------|------|----------|
| [Starship](https://starship.rs/) | 美观提示符，带 git 上下文 | [安装](https://starship.rs/guide/#🚀-installation) |
| [Fnm](https://github.com/Schniz/fnm) | 快速切换 Node 版本 | [安装](https://github.com/Schniz/fnm#installation) |
| [tmux](https://github.com/tmux/tmux) | 远程会话保持 | [安装](https://github.com/tmux/tmux/wiki) |

### 3️⃣ 自定义配置

编辑 `Config.ps1`：

```powershell
$global:HERMES_ROOT = "D:\Env"        # 你的根目录
$global:HERMES_APPS = "$global:HERMES_ROOT\UserScoop\apps"
```

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

## 🖥️ Tmux 管理器

`sss <host>` 打开交互式菜单：

```
┌─────────────────────────────────────────┐
│         REMOTE TMUX SESSION             │
├─────────────────────────────────────────┤
│  ▶  RESUME  — 附加到 'main'            │
│     ATTACH  — 仅附加到现有会话         │
│     NEW     — 创建新会话               │
│     LIST    — 查看所有会话              │
│     KILL    — 终止所有 tmux            │
│     EXIT    — 返回本地终端             │
└─────────────────────────────────────────┘
```

**操作：** `↑↓` 移动 · `Enter` 确认 · `q` 退出

---

## 🎨 配置说明

### 颜色方案

```powershell
$global:HERMES_CONF.Colors.Cyan  # 主色调
$global:HERMES_CONF.Colors.Gray  # 次要文字
$global:HERMES_CONF.Colors.Rst   # 重置格式
```

### 键盘码

```powershell
$global:HERMES_CONF.Keys.Up    # 38
$global:HERMES_CONF.Keys.Down  # 40
$global:HERMES_CONF.Keys.Enter # 13
$global:HERMES_CONF.Keys.Esc   # 27
```

### 随机语录

在 `$HERMES_ROOT\quotes.txt` 放置语录文件：

```
你喜欢的第一条语录
%
又一句激励的话
%
```

Shell 启动时会随机显示一条语录。✨

---

## 📜 开源协议

MIT © [Your Name](https://github.com/arbaleast)

---

> 💡 **提示：** 如果觉得有用，别忘了 star ⭐
