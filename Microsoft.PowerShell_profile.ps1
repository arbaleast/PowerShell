$ProfileTimer = [System.Diagnostics.Stopwatch]::StartNew()

$ActualRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

# 快速路径：仅加载配置和欢迎语（不导入完整模块）
. "$ActualRoot\ShellPrompt\Private\Initialize-Config.ps1"
. "$ActualRoot\ShellPrompt\Public\Initialize-Environment.ps1"
Show-UserScoopLogo

# 懒加载：sss 首次调用时才导入完整模块
function sss
{
    if (-not (Get-Module ShellPrompt))
    {
        $ModulePath = Join-Path $ActualRoot "ShellPrompt\ShellPrompt.psd1"
        Import-Module $ModulePath -ErrorAction SilentlyContinue
    }
    Start-TmuxSession @args
}

$ProfileTimer.Stop()
Write-Host "PowerShell Profile Loaded: $($ProfileTimer.ElapsedMilliseconds)ms" -ForegroundColor DarkGray

# 初始化 starship
Invoke-Expression (&starship init powershell)

# PSReadLine Tab 补全配置（确保最后执行）
Import-Module PSReadLine -ErrorAction SilentlyContinue
if (Get-Command Set-PSReadLineOption -ErrorAction SilentlyContinue)
{
    Set-PSReadLineOption -PredictionSource History
    Set-PSReadLineOption -EditMode Windows
    Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
    Set-PSReadLineKeyHandler -Key RightArrow -Function AcceptSuggestion
    Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
}
