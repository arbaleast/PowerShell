____  ____  ____  ____   ___  _____ ___ _     _____
|  _ \/ ___||  _ \|  _ \/ _ \|  ___|_ _| |   | ____|
| |_) \___ \| |_) | |_) | | | | |_   | || |   |  _|
|  __/ ___) |  __/|  _ <| |_| |  _|  | || |___| |___
|_|   |____/|_|   |_| \_\\___/|_|   |___|_____|_____|

```

### ⌨️ SSH + tmux Session Manager for PowerShell

> An interactive menu to manage remote tmux sessions via SSH. `sss <host>` to attach, create, or switch sessions.
> Powered by Starship prompt, Fnm node switching, and PSReadLine for a smoother terminal.

[![MIT License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-blue.svg)](https://github.com/PowerShell/PowerShell)
[![Starship](https://img.shields.io/badge/Starship-Prompt-8356ff.svg)](https://starship.rs)
[![Tmux](https://img.shields.io/badge/Tmux-Sessions-1BB91F.svg)](https://github.com/tmux/tmux)

[中文版](./README_zh.md) · [Report Bug](https://github.com/arbaleast/PowerShell/issues) · [Request Feature](https://github.com/arbaleast/PowerShell/issues)

---

## 📸 Real interface preview

Below is a sample terminal preview showing the prompt and remote tmux session menu. Actual appearance may vary by shell theme and current host configuration.

### Terminal preview

**Startup quote:**

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

### Tmux Manager (`sss <host>`)

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

**New session input:**

```

  session name (Enter = random):

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
- **Fallback SSH** — If remote host has no tmux, falls back to plain SSH login

### 📁 Everyday QoL

- **Quick Aliases** — `ll`, `..`, `~`, `which` for faster navigation
- **Modular Structure** — Self-contained `ShellPrompt/` module, single entry point

---

## 📂 Structure

```

PowerShell/
│
├── Microsoft.PowerShell_profile.ps1   # 🎯 Minimal entry — imports the module
├── data/
│   └── quotes.txt                     # 💬 Random startup quotes
├── README.md / README_zh.md
└── ShellPrompt/                       # 📦 Self-contained module
    ├── ShellPrompt.psd1              # 📋 Module manifest
    ├── ShellPrompt.psm1               # 🚪 Entry point (config → Private → Public → export)
    ├── Private/
    │   ├── Initialize-Config.ps1      # ⚙️  Global config ($UserScoop_CONF)
    │   ├── Invoke-ConsoleMenu.ps1      # 🖼️  Generic UI menu (no tmux knowledge)
    │   ├── Get-TmuxSessions.ps1        # 🔌 SSH → tmux ls parser
    │   └── Invoke-SessionSelector.ps1  # 🔀 Session picker submenu
    └── Public/
        ├── Initialize-Environment.ps1  # 🛠️  Starship / Fnm / PSReadLine + logo
        ├── Show-UserScoopLogo.ps1      # 🎨 Startup logo and quotes
        ├── Invoke-Reload.ps1           # 🔄 reload command
        ├── Set-ProfileAliases.ps1      # 🔗 ll, .., ~, which
        └── Start-TmuxSession.ps1       # 🚀 Tmux session manager (exported)

```

### Module Architecture

`ShellPrompt.psm1` loads files in strict order:

1. **Private/Initialize-Config.ps1** — sets up `$global:UserScoop_CONF` (colors, keys, SSH/Tmux options, quotes path)
2. **Private/** — internal helpers (Invoke-ConsoleMenu, Get-TmuxSessions, Invoke-SessionSelector)
3. **Public/** — user-facing commands (Initialize-Environment, Show-UserScoopLogo, Start-TmuxSession, reload)
4. **Export-ModuleMember** — only Public/*.ps1 functions are exported; Private is invisible to consumers

This enforces the MVC boundary: UI logic (`Invoke-ConsoleMenu`) knows nothing about tmux or SSH, keeping concerns separated.

---

## 🚀 Quick Start

### 1️⃣ Prerequisites

Ensure the following tools are installed on your system:

| Tool | Purpose | Install |
|------|---------|---------|
| [Starship](https://starship.rs/) | Pretty prompt with git context | [Guide](https://starship.rs/guide/#🚀-installation) |
| [Fnm](https://github.com/Schniz/fnm) | Fast Node version manager | [Guide](https://github.com/Schniz/fnm#installation) |
| [OpenSSH](https://docs.microsoft.com/windows-server/administration/openssh/openssh_install_firstuse) | SSH client for remote tmux | Built into Windows 10/11 or install via OpenSSH |
| [tmux](https://github.com/tmux/tmux) | Remote session persistence | [Installation](https://github.com/tmux/tmux/wiki/Installing) |

### 2️⃣ Install

```powershell
# Find your profile directory
$PROFILE

# Clone to a permanent location
git clone https://github.com/arbaleast/PowerShell.git D:\path\to\PowerShell

# Create a stub that loads the module
"`$PROFILE_DIR = 'D:\path\to\PowerShell'" | Out-File -Encoding UTF8 "`$PROFILE" -NoClobber
"`. `$PROFILE_DIR\Microsoft.PowerShell_profile.ps1" | Add-Content "`$PROFILE"

# Restart PowerShell or run:
reload
```

> `quotes.txt` lives at the repo root and is found automatically at load time.

### 3️⃣ Configure (Optional)

Edit `ShellPrompt/Private/Initialize-Config.ps1` to change colors, key codes, SSH timeout, or tmux session name.

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

Edit `ShellPrompt/Private/Initialize-Config.ps1` to customize:

## 📜 License

MIT © arbaleast

---

> __Tip:__ Star this repo if you find it useful! ⭐
