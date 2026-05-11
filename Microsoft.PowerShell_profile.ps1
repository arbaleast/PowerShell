$ProfileTimer = [System.Diagnostics.Stopwatch]::StartNew()
$UserScoop_ROOT = Split-Path -Parent $MyInvocation.MyCommand.Definition

. (Join-Path $UserScoop_ROOT "Config.ps1")
. (Join-Path $UserScoop_ROOT "Utils.ps1")
. (Join-Path $UserScoop_ROOT "Alias.ps1")

## 删除外面的 Import-Module，将 sss 改造为懒加载触发器
function sss
{
    # 仅在首次运行时导入模块
    if (-not (Get-Module -Name ShellPrompt))
    {
        Import-Module (Join-Path $global:UserScoop_ROOT "ShellPrompt.psd1") -ErrorAction SilentlyContinue
    }

    # 模块加载后，调用真实的函数
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
