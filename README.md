# Hermes G7 PowerShell Profile

A modular PowerShell profile with tmux session management, Starship prompt integration, and cross-platform tool support.

## Features

- **Modular Design** — Core components separated into focused scripts for easy maintenance
- **Lazy Loading** — Remote/tmux module loads only when `sss` command is first used
- **Tmux Manager** — Interactive menu for creating, attaching, and managing remote tmux sessions
- **Starship Prompt** — Cross-shell prompt customization with emoji-free output
- **Fnm Integration** — Fast Node Manager with auto-version switching on directory change
- **PSReadLine** — Enhanced shell experience with history-based autocompletion
- **Quick Aliases** — Common navigation shortcuts (`..`, `~`, `ll`, `which`)

## Structure

```
PowerShell/
├── .gitignore
├── Microsoft.PowerShell_profile.ps1 # Main entry point
├── Config.ps1                       # Global paths and configuration
├── Alias.ps1                        # Aliases and quick commands
├── Utils.ps1                        # Utility functions
└── Remote.ps1                       # Tmux session manager (lazy loaded)
```

## Setup

1. Copy all `.ps1` files to your PowerShell profile directory:
   ```powershell
   # Find your profile path
   $PROFILE

   # Copy files (adjust source path accordingly)
   Copy-Item -Path "D:\path\to\Hermes G7\*.ps1" -Destination (Split-Path $PROFILE -Parent)
   ```

2. Ensure dependencies are installed:
   - [Starship](https://starship.rs/) — Prompt
   - [Fnm](https://github.com/Schniz/fnm) — Node version manager
   - [tmux](https://github.com/tmux/tmux) — Terminal multiplexer (for remote sessions)

3. Edit `Config.ps1` to customize paths if needed:
   ```powershell
   $global:HERMES_ROOT = "D:\Env"        # Root directory
   $global:HERMES_APPS = "$global:HERES_ROOT\UserScoop\apps"  # Tools directory
   ```

## Usage

| Command | Description |
|---------|-------------|
| `sss <host>` | Start tmux manager for remote host |
| `reload` | Reload the profile |
| `ll` | List files (alias for `Get-ChildItem`) |
| `..` | Go to parent directory |
| `~` | Go to home directory |
| `which <cmd>` | Locate command (wraps `where.exe`) |

## Tmux Manager

The `sss` command provides an interactive menu for remote tmux sessions:

1. **RESUME** — Attach to `main` session, create if missing
2. **ATTACH** — Attach to existing `main` session only
3. **NEW** — Create new session with custom or random name
4. **LIST** — View all active sessions on remote host
5. **KILL** — Terminate all tmux processes on remote host
6. **EXIT** — Return to local terminal

Navigation: Arrow keys to move, Enter to select, `q` to quit.

## Configuration

### Colors

Defined in `Config.ps1`:
```powershell
$global:HERMES_CONF.Colors.Cyan  # Primary accent
$global:HERMES_CONF.Colors.Gray  # Secondary/muted text
$global:HERMES_CONF.Colors.Rst   # Reset formatting
```

### Keyboard Layout

```powershell
$global:HERMES_CONF.Keys.Up    # 38
$global:HERMES_CONF.Keys.Down  # 40
$global:HERMES_CONF.Keys.Enter # 13
$global:HERMES_CONF.Keys.Esc   # 27
```

### Quotes File

Place a `quotes.txt` file at `$HERMES_ROOT\quotes.txt` with entries separated by `%`:
```
First quote text here
%
Second quote text here
%
```

The logo displays a random quote on each shell start.

## License

MIT
