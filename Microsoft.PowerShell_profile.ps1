$ProfileTimer = [System.Diagnostics.Stopwatch]::StartNew()

# 显式声明为 script 作用域，确保在后续调用的函数中安全访问
$script:ActualRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

# 快速路径：仅加载配置和欢迎语
. "$script:ActualRoot\ShellPrompt\Private\Initialize-Config.ps1"
. "$script:ActualRoot\ShellPrompt\Public\Initialize-Environment.ps1"
Show-UserScoopLogo

# ============================================================
# 别名 — 保证在 ShellPrompt 模块懒加载前即可使用
# ============================================================
Set-Alias ll Get-ChildItem -ErrorAction SilentlyContinue
Set-Alias which where.exe -ErrorAction SilentlyContinue

# 优化 1：提取公共的懒加载逻辑 (DRY 原则)
function Ensure-ShellPrompt {
    if (-not (Get-Module ShellPrompt)) {
        $ModulePath = Join-Path $script:ActualRoot "ShellPrompt\ShellPrompt.psd1"
        Import-Module $ModulePath -ErrorAction SilentlyContinue
    }
}

# 懒加载命令
function sss {
    Ensure-ShellPrompt
    Start-TmuxSession @args
}

function water {
    Ensure-ShellPrompt
    Start-WaterReminder @args
}

function Get-WaterHistory {
    Ensure-ShellPrompt
    Get-WaterReminderHistory @args
}

# 优化 2：工具初始化加上可用性检查，并用 -join 替代 Out-String 以提升执行速度
# 初始化 starship
if (Get-Command starship -ErrorAction SilentlyContinue) {
    Invoke-Expression ((&starship init powershell) -join "`n")
}

# 初始化 fnm
if (Get-Command fnm -ErrorAction SilentlyContinue) {
    Invoke-Expression ((&fnm env --use-on-cd --shell powershell) -join "`n")
}

# 优化 3：PSReadLine 配置加上前置检查
if (Get-Module PSReadLine -ListAvailable) {
    Import-Module PSReadLine -ErrorAction SilentlyContinue
    Set-PSReadLineOption -PredictionSource History
    Set-PSReadLineOption -EditMode Windows
    Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
    Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
}

$ProfileTimer.Stop()
Write-Host "PowerShell Profile Loaded: $($ProfileTimer.ElapsedMilliseconds)ms" -ForegroundColor DarkGray
