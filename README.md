# �?PowerShell Profile

### ⌨️ A modular PowerShell profile with tmux, Starship & cross-platform tool support

[![MIT License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-blue.svg)](https://github.com/PowerShell/PowerShell)
[![Starship](https://img.shields.io/badge/Starship-Prompt-8356ff.svg)](https://starship.rs)
[![Tmux](https://img.shields.io/badge/Tmux-Sessions-1BB91F.svg)](https://github.com/tmux/tmux)

[中文版](./README_zh.md) · [Report Bug](https://github.com/arbaleast/PowerShell/issues) · [Request Feature](https://github.com/arbaleast/PowerShell/issues)

---

## �?Features

### 🚀 Performance
- **Lazy Loading** �?tmux module loads only when you first type `sss`
- **Fast Startup** �?Minimal footprint, loads in milliseconds

### 🛠�?Developer Tools
- **Starship Prompt** �?Cross-shell prompt with git awareness, Node version display
- **Fnm Integration** �?Auto-switch Node versions as you cd between projects
- **PSReadLine** �?History-based autocompletion, better navigation

### 🔧 Remote Sessions
- **Tmux Manager** �?Interactive menu for managing remote tmux sessions
- **Quick Connect** �?`sss <host>` to attach/resume/create sessions instantly

### 📁 Everyday QoL
- **Quick Aliases** �?`ll`, `..`, `~`, `which` for faster navigation
- **Modular Structure** �?Easy to customize, easy to maintain

---

## 📂 Structure

```
PowerShell/
�?
├── Microsoft.PowerShell_profile.ps1   # 🎯 Main entry �?loads everything
├── Config.ps1                       # ⚙️  Paths, colors, keyboard layout
├── Alias.ps1                        # 🔗 Aliases: ll, .., ~, reload, which
├── Utils.ps1                        # 🧰 Helpers: logo, cache, imports
└── Remote.ps1                       # 🖥�? Tmux session manager (lazy)
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

### 2️⃣ Set Up Directory Structure

Create the following directory layout (adjust paths as needed):

```
D:\Env\                    # �?$UserScoop_ROOT (root directory)
├── quotes.txt             # �?Startup quotes (optional)
└── UserScoop\
    └── apps\              # �?$UserScoop_APPS (tool directory)
        ├── starship\
        �?  └── current\
        �?      └── starship.exe
        └── fnm\
            └── current\
                └── fnm.exe
```

Or use any custom root path �?just update `Config.ps1` later.

### 3️⃣ Install Profile Files

```powershell
# Step A: Find your PowerShell profile directory
$PROFILE

# Step B: Copy all .ps1 files to your profile directory
#         Replace "D:\path\to\PowerShell" with your actual clone path
Copy-Item -Path "D:\path\to\PowerShell\*.ps1" `
           -Destination (Split-Path $PROFILE -Parent) `
           -Force

# Step C: Restart PowerShell or run:
reload
```

### 4️⃣ Configure (Optional)

Edit `Config.ps1` to match your setup:

```powershell
# Root directory �?where quotes.txt lives
$global:UserScoop_ROOT = "D:\Env"

# Tool directory �?where Starship, Fnm, etc. are installed
$global:UserScoop_APPS = "$global:UserScoop_ROOT\UserScoop\apps"
```

For color schemes and keyboard codes, see the [Configuration](#-configuration) section below.

---

## �?Commands

| Command | What it does |
|---------|-------------|
| `sss <host>` | 🖥�?Open tmux manager �?connect to remote host |
| `reload` | 🔄 Reload your PowerShell profile |
| `ll` | 📋 List files with details |
| `..` | ⬆️ Jump to parent directory |
| `~` | 🏠 Jump to home directory |
| `which <cmd>` | 🔍 Find where a command lives |

---

## 🖥�?Tmux Manager

`sss <host>` opens an interactive menu:

```
┌─────────────────────────────────────────�?
�?        REMOTE TMUX SESSION             �?
├─────────────────────────────────────────�?
�? �? RESUME  �?attach to 'main'          �?
�?    ATTACH  �?existing session only     �?
�?    NEW     �?create new session        �?
�?    LIST    �?view all sessions         �?
�?    KILL    �?terminate all tmux        �?
�?    EXIT    �?back to local             �?
└─────────────────────────────────────────�?
```

**Controls:** `↑↓` move · `Enter` select · `q` quit

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

Place a `quotes.txt` file at `$UserScoop_ROOT\quotes.txt`. Separate each quote with `%`:

```
Your favorite quote here
%
Another inspiring line
%
```

A random quote displays every time you start a new PowerShell session. �?

---

## 📜 License

MIT © arbaleast

---

> 💡 **Tip:** Star this repo if you find it useful! �?
