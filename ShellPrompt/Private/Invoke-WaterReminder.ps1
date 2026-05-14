# ============================================================
# Invoke-WaterReminder.ps1 - 喝水提醒核心逻辑
# 包含：天气感知、时段文案、Windows 通知、历史记录
# ============================================================

function Invoke-WaterReminder {
    [CmdletBinding()]
    param()

    $conf = $global:UserScoop_CONF.WaterReminder

    # ─────────────────────────────────────────────────────────
    # 1. 获取当前天气温度，计算调整间隔
    # ─────────────────────────────────────────────────────────
    $weatherMultiplier = 1.0
    if ($conf.WeatherEnabled) {
        try {
            $weatherUrl = "https://wttr.in/?format=j1"
            $weatherData = Invoke-RestMethod -Uri $weatherUrl -TimeoutSec 5 -ErrorAction Stop
            $tempC = $weatherData.current_condition[0].temp_C

            if ($tempC -lt 15) {
                $weatherMultiplier = 1.2    # 低温，延长间隔
            } elseif ($tempC -gt 35) {
                $weatherMultiplier = 0.5    # 极端高温，大幅缩短
            } elseif ($tempC -gt 28) {
                $weatherMultiplier = 0.7    # 高温，缩短间隔
            }
        } catch {
            $weatherMultiplier = 1.0
        }
    }

    $hour = (Get-Date).Hour

    # ─────────────────────────────────────────────────────────
    # 2. 根据时段调整基础间隔
    # ─────────────────────────────────────────────────────────
    $baseInterval = $conf.IntervalMin
    if ($hour -ge 11 -and $hour -lt 17) {
        $baseInterval = [Math]::Max(30, $baseInterval - 15)  # 午后缩短到45分钟
    }

    $adjustedInterval = [int]($baseInterval * $weatherMultiplier)

    # ─────────────────────────────────────────────────────────
    # 3. 生成时段感知文案
    # ─────────────────────────────────────────────────────────
    $title = "💧 喝水提醒"
    if ($hour -lt 9) {
        $body = "早安！新的一天从一杯水开始~ (建议 250ml)"
    } elseif ($hour -lt 12) {
        $body = "工作间隙，记得补充水分保持精力充沛！ (建议 250ml)"
    } elseif ($hour -lt 14) {
        $body = "午餐前喝杯水，有助于控制食量哦~ (建议 300ml)"
    } elseif ($hour -lt 17) {
        $body = "下午茶时间，水分补充不能少！ (建议 250ml)"
    } elseif ($hour -lt 20) {
        $body = "傍晚时分，身体需要持续补水~ (建议 250ml)"
    } else {
        $body = "晚间放松，一杯温水帮助消化~ (建议 200ml)"
    }

    if ($weatherMultiplier -lt 1.0) {
        $body += " [高温提醒：多补水]"
    }

    # ─────────────────────────────────────────────────────────
    # 4. 记录历史数据（先保存，确定是否超标）
    # ─────────────────────────────────────────────────────────
    $historyPath = $conf.HistoryPath
    $dataDir = Split-Path $historyPath -Parent

    if (-not (Test-Path $dataDir)) {
        New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
    }

    $today = (Get-Date).ToString("yyyy-MM-dd")
    $now = (Get-Date).ToString("HH:mm")

    $history = @{}
    
    # 使用 Mutex 防止并发写入
    $mutexName = "Global\WaterReminderHistory"
    $mutex = New-Object System.Threading.Mutex($false, $mutexName)
    try {
        $mutex.WaitOne(5000) | Out-Null  # 最多等待 5 秒

        if (Test-Path $historyPath) {
            $history = Get-Content $historyPath -Encoding UTF8 -Raw | ConvertFrom-Json -AsHashtable
        }

        if (-not $history.ContainsKey($today)) {
            $history[$today] = @{
                total   = 0
                records = @()
            }
        }

        # 添加记录
        $history[$today].records += @{
            time = $now
            ml   = 250
        }
        $history[$today].total += 250

        $history | ConvertTo-Json -Depth 10 | Set-Content -Path $historyPath -Encoding UTF8
    } finally {
        $mutex.ReleaseMutex()
        $mutex.Dispose()
    }

    # ─────────────────────────────────────────────────────────
    # 5. 发送 Windows 通知（根据是否超标调整内容）
    # ─────────────────────────────────────────────────────────
    $scriptPath = Join-Path $PSScriptRoot "Send-WaterNotification.ps1"
    
    # 检查是否超标
    $isOverGoal = $history[$today].total -gt $conf.DayGoalMl
    if ($isOverGoal) {
        $title = "🎉 今日目标已达成"
        $body = "今日已喝 $($history[$today].total)ml，超过了 $($conf.DayGoalMl)ml 的目标！继续加油~"
    }
    
    if (Test-Path $scriptPath) {
        Start-Process pwsh -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -Title `"$title`" -Body `"$body`" -Interval $adjustedInterval" -WindowStyle Hidden -ErrorAction SilentlyContinue
    }

    return @{
        Interval     = $adjustedInterval
        TotalToday   = $history[$today].total
        GoalProgress = [Math]::Round($history[$today].total / $conf.DayGoalMl * 100)
    }
}

function Get-WaterReminderStatus {
    [CmdletBinding()]
    param()

    $conf = $global:UserScoop_CONF.WaterReminder
    $historyPath = $conf.HistoryPath

    $today = (Get-Date).ToString("yyyy-MM-dd")

    if (Test-Path $historyPath) {
        $history = Get-Content $historyPath -Encoding UTF8 -Raw | ConvertFrom-Json -AsHashtable
        if ($history.ContainsKey($today)) {
            $todayData = $history[$today]
            $progress = [Math]::Round($todayData.total / $conf.DayGoalMl * 100)
            return @{
                Date         = $today
                Total        = $todayData.total
                Goal         = $conf.DayGoalMl
                Progress     = $progress
                RecordsCount = $todayData.records.Count
            }
        }
    }

    return @{
        Date         = $today
        Total        = 0
        Goal         = $conf.DayGoalMl
        Progress     = 0
        RecordsCount = 0
    }
}