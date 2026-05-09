[console]::InputEncoding = [console]::OutputEncoding = New-Object System.Text.UTF8Encoding
$OutputEncoding = [console]::InputEncoding
$ProfileTimer = [System.Diagnostics.Stopwatch]::StartNew()
$HermesRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition

. (Join-Path $HermesRoot "Config.ps1")
. (Join-Path $HermesRoot "Utils.ps1")
. (Join-Path $HermesRoot "Alias.ps1")

# 懒加载：仅在首次调用时加载 Remote.ps1
if (-not (Get-Command Start-TmuxSession -ErrorAction SilentlyContinue)) {
    . (Join-Path $HermesRoot "Remote.ps1")
}

function sss {
    Start-TmuxSession @args
}

if (Get-Command Show-UserScoopLogo -ErrorAction SilentlyContinue) {
    try { Show-UserScoopLogo } catch { }
}

$ProfileTimer.Stop()
Write-Host "PowerShell Profile Loaded: $($ProfileTimer.ElapsedMilliseconds)ms" -ForegroundColor DarkGray
