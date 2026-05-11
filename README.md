```
____  ____  ____  ____   ___  _____ ___ _     _____
|  _ \/ ___||  _ \|  _ \/ _ \|  ___|_ _| |   | ____|
| |_) \___ \| |_) | |_) | | | | |_   | || |   |  _|
|  __/ ___) |  __/|  _ <| |_| |  _|  | || |___| |___
|_|   |____/|_|   |_| \_\\___/|_|   |___|_____|_____|
```

### ⌨️ A modular PowerShell profile with tmux, Starship & cross-platform tool support

[![MIT License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-blue.svg)](https://github.com/PowerShell/PowerShell)
[![Starship](https://img.shields.io/badge/Starship-Prompt-8356ff.svg)](https://starship.rs)
[![Tmux](https://img.shields.io/badge/Tmux-Sessions-1BB91F.svg)](https://github.com/tmux/tmux)

[中文版](./README_zh.md) · [Report Bug](https://github.com/arbaleast/PowerShell/issues) · [Request Feature](https://github.com/arbaleast/PowerShell/issues)

---

## 📸 Screenshot

```
  * ACTIVE -- 14:32

    💬 代码是写给人看的，顺便给机器运行。

  ----------------------------------------------
  
  ~/Projects/PowerShell on main偏
  ❯ _
```

**Tmux Manager (`sss <host>`):**

```
┌─────────────────────────────────────────┐
│         REMOTE TMUX SESSION             │
├─────────────────────────────────────────┤
│  ▶  RESUME  — attach to 'main'         │
│     ATTACH  — existing session only     │
│     NEW     — create new session        │
│     LIST   — view all sessions          │
│     KILL   — terminate all tmux         │
│  ▶  [q] EXIT  — back to local              │
└─────────────────────────────────────────┘
        ↑↓ move  ·  Enter select  ·  q quit
```

---

## ✨ Features

### 🚀 Performance
- **Lazy Loading** — tmux module loads only when you first type `sss`
- **Fast Startup** — Minimal footprint, loads in milliseconds

### 🛠️ Developer Tools
- **Starship Prompt** — Cross-shell prompt with git awareness, Node version display
- **Fnm Integration** — Auto-switch Node versions as you cd between projects
- **PSReadLine** — History-based autocompletion, better navigation

### 🔧 Remote Sessions
- **Tmux Manager** — Interactive menu for managing remote tmux sessions
- **Quick Connect** — `sss <host>` to attach/resume/create sessions instantly

### 📁 Everyday QoL
- **Quick Aliases** — `ll`, `..`, `~`, `which` for faster navigation
- **Modular Structure** — Easy to customize, easy to maintain

---

## 📂 Structure

```
PowerShell/
│
├── Microsoft.PowerShell_profile.ps1   # 🎯 Main entry — loads everything
├── Config.ps1                       # ⚙️  Paths, colors, keyboard layout
├── Alias.ps1                        # 🔗 Aliases: ll, .., ~, reload, which
├── Utils.ps1                        # 🧰 Helpers: logo, cache, imports
├── Remote.ps1                       # 🖥️  Tmux session manager (lazy)
└── quotes.txt                       # 💬 Random startup quotes
```

---

## 🚀 Quick Start

### 1️⃣ Prerequisites

Ensure the following tools are installed on your system:

| Tool | Purpose | Install |
|------|---------|---------|
| [Starship](https://starship.rs/) | Pretty prompt with git context | [Guide](https://starship.rs/guide/#🚀-installation) |
| [Fnm](https://github.com/Schniz/fnm) | Fast Node version manager | [Guide](https://github.com/Schniz/fnm#installation) |
| [tmux](https://github.com/tmux/tmux) | Remote session persistence | [Wiki](https://github.com/tmux/tmux/wiki) |

### 2️⃣ Install Profile Files

```powershell
# Step A: Find your PowerShell profile directory
$PROFILE

# Step B: Copy all files to your profile directory
#         Replace "D:\path\to\PowerShell" with your actual clone path
Copy-Item -Path "D:\path\to\PowerShell\*" `
           -Destination (Split-Path $PROFILE -Parent) `
           -Force

# Step C: Restart PowerShell or run:
reload
```

> 💡 **Note:** `quotes.txt` will be loaded automatically from the script directory.

### 3️⃣ Configure (Optional)

Edit `Config.ps1` to customize:

```powershell
# Default paths (auto-detected from script location)
$global:UserScoop_ROOT = $PSScriptRoot  # Where quotes.txt lives
$global:UserScoop_APPS = "...\apps"     # Where tools are installed
```

For color schemes and keyboard codes, see the [Configuration](#-configuration) section below.

---

## ⚡ Commands

| Command | What it does |
|---------|-------------|
| `sss <host>` | 🖥️ Open tmux manager → connect to remote host |
| `reload` | 🔄 Reload your PowerShell profile |
| `ll` | 📋 List files with details |
| `..` | ⬆️ Jump to parent directory |
| `~` | 🏠 Jump to home directory |
| `which <cmd>` | 🔍 Find where a command lives |

---

## 🎨 Configuration

### Directory Paths

```powershell
$global:UserScoop_ROOT                  # Root directory (quotes.txt lives here)
$global:UserScoop_APPS                 # Tool directory (Starship, Fnm, etc.)
```

### Colors

```powershell
$global:UserScoop_CONF.Colors.Cyan  # Primary accent
$global:UserScoop_CONF.Colors.Gray  # Secondary text
$global:UserScoop_CONF.Colors.Rst   # Reset formatting
```

### Keyboard Codes

```powershell
$global:UserScoop_CONF.Keys.Up    # 38
$global:UserScoop_CONF.Keys.Down  # 40
$global:UserScoop_CONF.Keys.Enter # 13
$global:UserScoop_CONF.Keys.Esc   # 27
```

### Random Quotes

Quotes are loaded from `quotes.txt` in the script directory. Separate each quote with `%`:

```text
💬 代码是写给人看的，顺便给机器运行。
%
🔥 Talk is cheap, show me the code.
%
⚡ Stay hungry, stay foolish.
%
✨ 简洁是智慧的灵魂。
```

A random quote displays every time you start a new PowerShell session. ✨

---

## 📜 License

MIT © arbaleast

---

> 💡 **Tip:** Star this repo if you find it useful! ⭐
