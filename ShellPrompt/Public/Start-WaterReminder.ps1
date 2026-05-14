# ============================================================
# Start-WaterReminder.ps1 - 喝水提醒后台任务
# 启动智能喝水提醒循环，支持 Ctrl+C 中断
# ============================================================

function Start-WaterReminder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [int]$IntervalMinutes = $global:UserScoop_CONF.WaterReminder.IntervalMin,

        [Parameter(Mandatory = $false)]
        [switch]$Status,

        [Parameter(Mandatory = $false)]
        [switch]$Background
    )

    $conf = $global:UserScoop_CONF.WaterReminder

    # 后台模式：静默运行，仅记录日志
    if ($Background) {
        $logPath = $conf.LogPath
        $logDir = Split-Path $logPath -Parent
        if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
        
        while ($true) {
            try {
                # 安静时段则休眠
                $hour = (Get-Date).Hour
                if ($hour -ge $conf.QuietHoursStart -or $hour -lt $conf.QuietHoursEnd) {
                    Start-Sleep -Seconds 3600
                    continue
                }
                
                # 发送提醒并记录
                $result = Invoke-WaterReminder
                "$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) - 喝水提醒已发送，今日进度: $($result.TotalToday)ml" | Add-Content -Path $logPath -Encoding UTF8
                Start-Sleep -Seconds ($result.Interval * 60)
            } catch {
                "$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) - Error: $_" | Add-Content -Path $logPath -Encoding UTF8
                Start-Sleep -Seconds 60
            }
        }
        return
    }

    # 显示状态
    if ($Status) {
        $stat = Get-WaterReminderStatus
        $rst = "`e[0m"
        $green = $global:UserScoop_CONF.Colors.FreshGreen
        $mid = $global:UserScoop_CONF.Colors.MidGray

        Write-Host ""
        Write-Host "  ${green}💧 喝水提醒状态${rst}"
        Write-Host "  ${mid}──────────────────────${rst}"
        Write-Host "  日期: $($stat.Date)"
        Write-Host "  今日摄入: $($stat.Total) / $($stat.Goal) ml"
        Write-Host "  目标进度: $($stat.Progress)%"
        Write-Host "  记录次数: $($stat.RecordsCount)"
        Write-Host ""
        return
    }

    # 检查安静时段
    function Test-QuietHours {
        $hour = (Get-Date).Hour
        $start = $conf.QuietHoursStart
        $end = $conf.QuietHoursEnd

        if ($start -gt $end) {
            return ($hour -ge $start) -or ($hour -lt $end)
        } else {
            return ($hour -ge $start) -and ($hour -lt $end)
        }
    }

    # 计算距离下次安静时段的时间
    function Get-NextActiveTime {
        $now = Get-Date
        $hour = $now.Hour
        $end = $conf.QuietHoursEnd

        if ($hour -lt $end) {
            return $now
        } else {
            return (Get-Date -Hour $end -Minute 0 -Second 0).AddDays(1)
        }
    }

    Write-Host ""
    Write-Host "  💧 喝水提醒已启动 (Ctrl+C 停止)" -ForegroundColor Cyan
    Write-Host "  每日目标: $($conf.DayGoalMl) ml" -ForegroundColor DarkGray
    Write-Host "  基础间隔: ${IntervalMinutes} 分钟" -ForegroundColor DarkGray

    $spinner = @('⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏')
    $spinnerIdx = 0

    while ($true) {
        try {
            # 检查安静时段
            if (Test-QuietHours) {
                $nextActive = Get-NextActiveTime
                $waitSec = [int]($nextActive - (Get-Date)).TotalSeconds

                Write-Host ""
                Write-Host "  🌙 夜间休眠中，下次于 $((Get-Date).AddSeconds($waitSec).ToString('HH:mm')) 提醒" -ForegroundColor DarkGray

                Start-Sleep -Seconds $waitSec
                continue
            }

            # 发送提醒
            $result = Invoke-WaterReminder

            Write-Host ""
            Write-Host "  ✓ 提醒已发送 | 今日进度: $($result.TotalToday) / $($conf.DayGoalMl) ml ($($result.GoalProgress)%)" -ForegroundColor Green

            # 计算等待时间
            $waitSeconds = $result.Interval * 60

            # 倒计时显示
            while ($waitSeconds -gt 0) {
                $mins = [int]($waitSeconds / 60)
                $secs = $waitSeconds % 60

                $spin = $spinner[$spinnerIdx % $spinner.Length]
                Write-Host "`r  ${spin} 下次提醒: ${mins}:$($secs.ToString('00'))  " -NoNewline -ForegroundColor DarkGray
                $spinnerIdx++
                Start-Sleep -Seconds 1
                $waitSeconds--

                # 每分钟检查安静时段
                if ($waitSeconds % 60 -eq 0 -and (Test-QuietHours)) {
                    Write-Host ""  # 换行避免残留
                    break
                }
                
                # 避免长时间运行后字符堆积，每分钟清一次屏幕
                if ($waitSeconds % 60 -eq 59) {
                    # 不换行，让 \r 在下一轮覆盖
                }
            }
            
            # 循环结束时确保换行
            Write-Host ""
        } catch [OperationCanceledException] {
            Write-Host ""
            Write-Host "  👋 喝水提醒已停止" -ForegroundColor Cyan
            break
        } catch {
            Write-Host "  [Error] $_" -ForegroundColor Red
            Start-Sleep -Seconds 5
        }
    }
}

function Get-WaterReminderHistory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [int]$Days = 7
    )

    $conf = $global:UserScoop_CONF.WaterReminder
    $historyPath = $conf.HistoryPath

    if (-not (Test-Path $historyPath)) {
        Write-Host "  暂无历史记录" -ForegroundColor Yellow
        return
    }

    $history = Get-Content $historyPath -Encoding UTF8 -Raw | ConvertFrom-Json -AsHashtable

    $rst = "`e[0m"
    $green = $global:UserScoop_CONF.Colors.FreshGreen
    $mid = $global:UserScoop_CONF.Colors.MidGray

    Write-Host ""
    Write-Host "  ${green}💧 喝水历史 (最近 ${Days} 天)${rst}"
    Write-Host "  ${mid}$('─' * 40)${rst}"

    $startDate = (Get-Date).AddDays(-$Days)

    foreach ($dateStr in ($history.Keys | Sort-Object -Descending)) {
        if ([DateTime]$dateStr -lt $startDate) { continue }

        $dayData = $history[$dateStr]
        $progress = [Math]::Round($dayData.total / $conf.DayGoalMl * 100)
        $barLen = [Math]::Min(20, [Math]::Max(0, [Math]::Floor($progress / 5)))
        $bar = "█" * $barLen + "░" * (20 - $barLen)

        $statusColor = if ($progress -ge 100) { "Green" } elseif ($progress -ge 50) { "Yellow" } else { "DarkGray" }

        Write-Host "  $($dateStr) [${bar}] $($dayData.total)ml" -ForegroundColor $statusColor
    }

    Write-Host ""
}

Export-ModuleMember -Function Start-WaterReminder, Get-WaterReminderHistory