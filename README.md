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
├── ShellPrompt.psd1                   # 📦 Module manifest
├── ShellPrompt.psm1                   # 📦 Module entry point
├── Config.ps1                         # ⚙️  Paths, colors, keyboard layout
├── Alias.ps1                          # 🔗 Aliases: ll, .., ~, reload, which
├── Utils.ps1                          # 🧰 Helpers: logo, terminal init
├── Private/
│   ├── Invoke-ConsoleMenu.ps1         # 🖼️  Generic UI menu component
│   ├── Get-TmuxSessions.ps1           # 🔌 SSH → tmux ls
│   ├── Get-TmuxMenuItems.ps1           # 📋 Menu state builder
│   └── Invoke-SessionSelector.ps1      # 🔀 Session picker submenu
├── Public/
│   └── Start-TmuxSession.ps1           # 🚀 Entry point (exported)
└── quotes.txt                         # 💬 Random startup quotes
```

### Module Architecture

`ShellPrompt.psm1` loads Private functions first (internal use), then Public functions. Only `Start-TmuxSession` is exported via `Export-ModuleMember`. All other functions are private implementation details.

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

# Step B: Clone this repo to a permanent location
git clone https://github.com/arbaleast/PowerShell.git D:\path\to\PowerShell

# Step C: Create a stub in your profile directory that loads the real config
# Replace "D:\path\to\PowerShell" with your actual clone path
"`$PROFILE_DIR = 'D:\path\to\PowerShell'" | Out-File -Encoding UTF8 "`$PROFILE" -NoClobber
"`. `$PROFILE_DIR\Microsoft.PowerShell_profile.ps1" | Add-Content "`$PROFILE"

# Step D: Restart PowerShell or run:
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

Edit `Config.ps1` to customize:

## 📜 License

MIT © arbaleast

---

> 💡 **Tip:** Star this repo if you find it useful! ⭐
