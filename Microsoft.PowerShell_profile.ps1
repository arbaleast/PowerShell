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

# wr 命令：专门启动后台喝水提醒（独立于交互式 water）
function wr {
    if (-not (Get-Module ShellPrompt)) {
        $ModulePath = Join-Path $ActualRoot "ShellPrompt\ShellPrompt.psd1"
        Import-Module $ModulePath -ErrorAction SilentlyContinue
    }
    # 检查是否已有后台进程
    $pidFile = "$env:TEMP\.water-reminder.pid"
    if (Test-Path $pidFile) {
        $oldPid = Get-Content $pidFile -Raw
        if ($oldPid -and (Get-Process -Id $oldPid -ErrorAction SilentlyContinue)) {
            Write-Host " [OK] 后台喝水提醒已在运行中 (PID: $oldPid)" -ForegroundColor DarkGray
            return
        }
        Remove-Item -Path $pidFile -Force -ErrorAction SilentlyContinue
    }
    # 后台模式：在新进程中运行，避免阻塞当前会话
    $psExe = Get-PowerShellExe
    $arg = "-NoProfile -WorkingDirectory `"$ActualRoot`" -Command `"& {`$env:WATER_PID = `$PID; `$pidFile = '$pidFile'; `$global:UserScoop_ROOT = '$ActualRoot'; Import-Module '$ModulePath'; Set-Content -Path `$pidFile -Value `$PID -Force; Start-WaterReminder -Background}`""
    $process = Start-Process -FilePath $psExe -ArgumentList $arg -WindowStyle Hidden -PassThru
    if ($process -and $process.HasExited) {
        Write-Host " [!] 后台喝水提醒启动失败，请查看日志或手动检查" -ForegroundColor Yellow
        return
    }
    Write-Host " [OK] 后台喝水提醒已启动 (PID: $($process.Id))" -ForegroundColor DarkGray
}

# water 命令：交互式喝水提醒（不涉及后台进程）
function water {
    if (-not (Get-Module ShellPrompt)) {
        $ModulePath = Join-Path $ActualRoot "ShellPrompt\ShellPrompt.psd1"
        Import-Module $ModulePath -ErrorAction SilentlyContinue
    }
    Start-WaterReminder @args
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

# 初始化 fnm (Node.js 版本管理器)
fnm env --use-on-cd --shell powershell | Out-String | Invoke-Expression

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
