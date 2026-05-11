$ProfileTimer = [System.Diagnostics.Stopwatch]::StartNew()

$ActualRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ModulePath = Join-Path $ActualRoot "ShellPrompt\ShellPrompt.psd1"

if (Test-Path $ModulePath)
{
    Import-Module $ModulePath -ErrorAction Stop
} else
{
    Write-Warning "Module not found: $ModulePath"
}

# 初始化终端环境（Starship / Fnm / PSReadLine）
Initialize-Environment

# 显示欢迎语
Show-UserScoopLogo

# 快捷入口
function sss
{ Start-TmuxSession @args 
}

$ProfileTimer.Stop()
Write-Host "PowerShell Profile Loaded: $($ProfileTimer.ElapsedMilliseconds)ms" -ForegroundColor DarkGray
