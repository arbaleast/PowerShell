$ProfileTimer = [System.Diagnostics.Stopwatch]::StartNew()

Import-Module "$PSScriptRoot\ShellPrompt\ShellPrompt.psd1" -ErrorAction SilentlyContinue

if (Get-Command Show-UserScoopLogo -ErrorAction SilentlyContinue)
{
    try
    { Show-UserScoopLogo 
    } catch
    { 
    }
}

function sss
{ Start-TmuxSession @args 
}

$ProfileTimer.Stop()
Write-Host "PowerShell Profile Loaded: $($ProfileTimer.ElapsedMilliseconds)ms" -ForegroundColor DarkGray
