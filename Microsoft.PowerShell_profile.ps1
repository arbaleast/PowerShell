$ProfileTimer = [System.Diagnostics.Stopwatch]::StartNew()

$ActualRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

# 快速路径：仅加载配置和欢迎语（不导入完整模块）
. "$ActualRoot\ShellPrompt\Private\Initialize-Config.ps1"
. "$ActualRoot\ShellPrompt\Public\Initialize-Environment.ps1"
Show-UserScoopLogo

# 懒加载：sss 首次调用时才导入完整模块
function sss {
    if (-not (Get-Module ShellPrompt)) {
        $ModulePath = Join-Path $ActualRoot "ShellPrompt\ShellPrompt.psd1"
        Import-Module $ModulePath -ErrorAction SilentlyContinue
    }
    Start-TmuxSession @args
}

# water 命令懒加载
function water {
    if (-not (Get-Module ShellPrompt)) {
        $ModulePath = Join-Path $ActualRoot "ShellPrompt\ShellPrompt.psd1"
        Import-Module $ModulePath -ErrorAction SilentlyContinue
    }
    if ($args -contains '-Background') {
        # 检查是否已有后台进程
        $pidFile = "$env:TEMP\.water-reminder.pid"
        if (Test-Path $pidFile) {
            $oldPid = Get-Content $pidFile -Raw
            if ($oldPid -and (Get-Process -Id $oldPid -ErrorAction SilentlyContinue)) {
                Write-Host " [OK] 后台喝水提醒已在运行中 (PID: $oldPid)" -ForegroundColor DarkGray
                return
            }
        }
        # 后台模式：在新进程中运行，避免阻塞当前会话
        Start-Process pwsh -ArgumentList "-NoProfile -Command `"& {`$env:WATER_PID = `$PID; `$pidFile = '$pidFile'; `$global:UserScoop_ROOT = '$ActualRoot'; Import-Module '$ModulePath'; Set-Content -Path `$pidFile -Value `$PID -Force; Start-WaterReminder -Background}`"" -WindowStyle Hidden
        Write-Host " [OK] 后台喝水提醒已启动" -ForegroundColor DarkGray
    } else {
        Start-WaterReminder @args
    }
}

# Get-WaterHistory 命令懒加载（原 history 命令被覆盖，改用 Get-WaterHistory 避免冲突）
function Get-WaterHistory {
    if (-not (Get-Module ShellPrompt)) {
        $ModulePath = Join-Path $ActualRoot "ShellPrompt\ShellPrompt.psd1"
        Import-Module $ModulePath -ErrorAction SilentlyContinue
    }
    Get-WaterReminderHistory @args
}

# reload 命令懒加载
function reload {
    if (-not (Get-Module ShellPrompt)) {
        $ModulePath = Join-Path $ActualRoot "ShellPrompt\ShellPrompt.psd1"
        Import-Module $ModulePath -ErrorAction SilentlyContinue
    }
    . $PROFILE
}

$ProfileTimer.Stop()
Write-Host "PowerShell Profile Loaded: $($ProfileTimer.ElapsedMilliseconds)ms" -ForegroundColor DarkGray

# 初始化 starship
Invoke-Expression (&starship init powershell)

# PSReadLine Tab 补全配置（确保最后执行）
Import-Module PSReadLine -ErrorAction SilentlyContinue
if (Get-Command Set-PSReadLineOption -ErrorAction SilentlyContinue) {
    Set-PSReadLineOption -PredictionSource History
    Set-PSReadLineOption -EditMode Windows
    Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
    # Set-PSReadLineKeyHandler -Key RightArrow -Function AcceptSuggestion  # 预测建议
    Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
}
