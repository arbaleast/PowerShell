# ⚡ PowerShell Profile

### ⌨️ A modular PowerShell profile with tmux, Starship & cross-platform tool support

[![MIT License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-blue.svg)](https://github.com/PowerShell/PowerShell)
[![Starship](https://img.shields.io/badge/Starship-Prompt-8356ff.svg)](https://starship.rs)
[![Tmux](https://img.shields.io/badge/Tmux-Sessions-1BB91F.svg)](https://github.com/tmux/tmux)

[中文版](./README_zh.md) · [Report Bug](https://github.com/arbaleast/PowerShell/issues) · [Request Feature](https://github.com/arbaleast/PowerShell/issues)

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
└── Remote.ps1                       # 🖥️  Tmux session manager (lazy)
```

---

## 🚀 Quick Start

### 1️⃣ Install

```powershell
# Find your profile path
$PROFILE

# Copy files (adjust the source path)
Copy-Item -Path "D:\path\to\PowerShell\*.ps1" -Destination (Split-Path $PROFILE -Parent)
```

### 2️⃣ Dependencies

| Tool | Why you need it | One-liner |
|------|----------------|-----------|
| [Starship](https://starship.rs/) | Pretty prompt with git context | [Install](https://starship.rs/guide/#🚀-installation) |
| [Fnm](https://github.com/Schniz/fnm) | Fast Node version switching | [Install](https://github.com/Schniz/fnm#installation) |
| [tmux](https://github.com/tmux/tmux) | Remote session persistence | [Install](https://github.com/tmux/tmux/wiki) |

### 3️⃣ Customize

Edit `Config.ps1`:

```powershell
$global:HERMES_ROOT = "D:\Env"        # Your root directory
$global:HERMES_APPS = "$global:HERMES_ROOT\UserScoop\apps"
```

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

## 🖥️ Tmux Manager

`sss <host>` opens an interactive menu:

```
┌─────────────────────────────────────────┐
│         REMOTE TMUX SESSION             │
├─────────────────────────────────────────┤
│  ▶  RESUME  — attach to 'main'          │
│     ATTACH  — existing session only     │
│     NEW     — create new session        │
│     LIST    — view all sessions         │
│     KILL    — terminate all tmux        │
│     EXIT    — back to local             │
└─────────────────────────────────────────┘
```

**Controls:** `↑↓` move · `Enter` select · `q` quit

---

## 🎨 Configuration

### Colors

```powershell
$global:HERMES_CONF.Colors.Cyan  # Primary accent
$global:HERMES_CONF.Colors.Gray  # Secondary text
$global:HERMES_CONF.Colors.Rst   # Reset formatting
```

### Keyboard Codes

```powershell
$global:HERMES_CONF.Keys.Up    # 38
$global:HERMES_CONF.Keys.Down  # 40
$global:HERMES_CONF.Keys.Enter # 13
$global:HERMES_CONF.Keys.Esc   # 27
```

### Random Quotes

Drop a `quotes.txt` at `$HERMES_ROOT\quotes.txt`:

```
Your favorite quote here
%
Another inspiring line
%
```

A random quote shows on shell startup. ✨

---

## 📜 License

MIT © [Your Name](https://github.com/arbaleast)

---

> 💡 **Tip:** Star this repo if you find it useful! ⭐
