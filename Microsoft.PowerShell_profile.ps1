$ProfileTimer = [System.Diagnostics.Stopwatch]::StartNew()
$UserScoop_ROOT = Split-Path -Parent $MyInvocation.MyCommand.Definition

. (Join-Path $UserScoop_ROOT "Config.ps1")
. (Join-Path $UserScoop_ROOT "Utils.ps1")
. (Join-Path $UserScoop_ROOT "Alias.ps1")

# 导入 ShellPrompt 模块（包含所有 tmux/SSH 交互逻辑）
Import-Module (Join-Path $UserScoop_ROOT "ShellPrompt.psd1") -ErrorAction SilentlyContinue

function sss
{
    Start-TmuxSession @args
}

if (Get-Command Show-UserScoopLogo -ErrorAction SilentlyContinue)
{
    try
    { Show-UserScoopLogo
    } catch
    {
    }
}

$ProfileTimer.Stop()
Write-Host "PowerShell Profile Loaded: $($ProfileTimer.ElapsedMilliseconds)ms" -ForegroundColor DarkGray
