$ProfileTimer = [System.Diagnostics.Stopwatch]::StartNew()
$HermesRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition

. (Join-Path $HermesRoot "Config.ps1")
. (Join-Path $HermesRoot "Utils.ps1")
. (Join-Path $HermesRoot "Alias.ps1")

# 懒加载：仅在用户首次输入 sss 时，才去加载 Remote.ps1
function sss {
    . (Join-Path $HermesRoot "Remote.ps1")
    Start-TmuxSession @args
}

if (Get-Command Show-HermesLogo -ErrorAction SilentlyContinue) { Show-HermesLogo }

$ProfileTimer.Stop()
Write-Host "Hermes G7 Loaded: $($ProfileTimer.ElapsedMilliseconds)ms" -ForegroundColor DarkGray
