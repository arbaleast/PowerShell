# 鈿?PowerShell Profile

### 鈱笍 A modular PowerShell profile with tmux, Starship & cross-platform tool support

[![MIT License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-blue.svg)](https://github.com/PowerShell/PowerShell)
[![Starship](https://img.shields.io/badge/Starkship-Prompt-8356ff.svg)](https://starship.rs)
[![Tmux](https://img.shields.io/badge/Tmux-Sessions-1BB91F.svg)](https://github.com/tmux/tmux)

[涓枃鐗圿(./README_zh.md) 路 [Report Bug](https://github.com/arbaleast/PowerShell/issues) 路 [Request Feature](https://github.com/arbaleast/PowerShell/issues)

---

## 鉁?Features

### 馃殌 Performance
- **Lazy Loading** 鈥?tmux module loads only when you first type `sss`
- **Fast Startup** 鈥?Minimal footprint, loads in milliseconds

### 馃洜锔?Developer Tools
- **Starship Prompt** 鈥?Cross-shell prompt with git awareness, Node version display
- **Fnm Integration** 鈥?Auto-switch Node versions as you cd between projects
- **PSReadLine** 鈥?History-based autocompletion, better navigation

### 馃敡 Remote Sessions
- **Tmux Manager** 鈥?Interactive menu for managing remote tmux sessions
- **Quick Connect** 鈥?`sss <host>` to attach/resume/create sessions instantly

### 馃搧 Everyday QoL
- **Quick Aliases** 鈥?`ll`, `..`, `~`, `which` for faster navigation
- **Modular Structure** 鈥?Easy to customize, easy to maintain

---

## 馃搨 Structure

```
PowerShell/
鈹?
鈹溾攢鈹€ Microsoft.PowerShell_profile.ps1   # 馃幆 Main entry 鈥?loads everything
鈹溾攢鈹€ Config.ps1                       # 鈿欙笍  Paths, colors, keyboard layout
鈹溾攢鈹€ Alias.ps1                        # 馃敆 Aliases: ll, .., ~, reload, which
鈹溾攢鈹€ Utils.ps1                        # 馃О Helpers: logo, cache, imports
鈹斺攢鈹€ Remote.ps1                       # 馃枼锔? Tmux session manager (lazy)
```

---

## 馃殌 Quick Start

### 1锔忊儯 Prerequisites

Ensure the following tools are installed on your system:

| Tool | Purpose | Install |
|------|---------|---------|
| [Starship](https://starship.rs/) | Pretty prompt with git context | [Guide](https://starship.rs/guide/#馃殌-installation) |
| [Fnm](https://github.com/Schniz/fnm) | Fast Node version manager | [Guide](https://github.com/Schniz/fnm#installation) |
| [tmux](https://github.com/tmux/tmux) | Remote session persistence | [Wiki](https://github.com/tmux/tmux/wiki) |

### 2锔忊儯 Set Up Directory Structure

Create the following directory layout (adjust paths as needed):

```
D:\Env\                    # 鈫?$UserScoop_ROOT (root directory)
鈹溾攢鈹€ quotes.txt             # 鈫?Startup quotes (optional)
鈹斺攢鈹€ UserScoop\
    鈹斺攢鈹€ apps\              # 鈫?$UserScoop_APPS (tool directory)
        鈹溾攢鈹€ starship\
        鈹?  鈹斺攢鈹€ current\
        鈹?      鈹斺攢鈹€ starship.exe
        鈹斺攢鈹€ fnm\
            鈹斺攢鈹€ current\
                鈹斺攢鈹€ fnm.exe
```

Or use any custom root path 鈥?just update `Config.ps1` later.

### 3锔忊儯 Install Profile Files

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

### 4锔忊儯 Configure (Optional)

Edit `Config.ps1` to match your setup:

```powershell
# Root directory 鈥?where quotes.txt lives
$global:UserScoop_ROOT = "D:\Env"

# Tool directory 鈥?where Starship, Fnm, etc. are installed
$global:UserScoop_APPS = "$global:UserScoop_ROOT\UserScoop\apps"
```

For color schemes and keyboard codes, see the [Configuration](#-configuration) section below.

---

## 鈿?Commands

| Command | What it does |
|---------|---------------|
| `sss <host>` | 馃枼锔?Open tmux manager 鈫?connect to remote host |
| `reload` | 馃攧 Reload your PowerShell profile |
| `ll` | 馃搵 List files with details |
| `..` | 猬嗭笍 Jump to parent directory |
| `~` | 馃彔 Jump to home directory |
| `which <cmd>` | 馃攳 Find where a command lives |

---

## 馃枼锔?Tmux Manager

`sss <host>` opens an interactive menu:

```
鈹屸攢鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹?
鈹?        REMOTE TMUX SESSION             鈹?
鈹溾攢鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹?
鈹? 鈻? RESUME  鈥?attach to 'main'          鈹?
鈹?    ATTACH  鈥?existing session only     鈹?
鈹?    NEW     鈥?create new session        鈹?
鈹?    LIST    鈥?view all sessions         鈹?
鈹?    KILL    鈥?terminate all tmux        鈹?
鈹?    EXIT    鈥?back to local             鈹?
鈹斺攢鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹?
```

**Controls:** `鈫戔啌` move 路 `Enter` select 路 `q` quit

---

## 馃帹 Configuration

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

A random quote displays every time you start a new PowerShell session. 鉁?

---

## 馃摐 License

MIT 漏 [Your Name](https://github.com/arbaleast)

---

> 馃挕 **Tip:** Star this repo if you find it useful! 猸?
