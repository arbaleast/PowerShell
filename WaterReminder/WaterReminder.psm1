# ============================================================
# WaterReminder.psm1 - 喝水提醒核心模块
# 包含：天气感知、时段文案、历史记录、通知发送
# ============================================================

# 加载配置
$script:Config = & (Join-Path $PSScriptRoot 'config.ps1')

function Get-Config {
    # 返回配置，支持路径变量展开
    $conf = $script:Config.Clone()
    
    # 展开路径变量
    $dataDir = $ExecutionContext.InvokeCommand.ExpandString($conf.DataDir)
    $logDir = $ExecutionContext.InvokeCommand.ExpandString($conf.LogDir)
    
    $conf.DataDir = $dataDir
    $conf.LogDir = $logDir
    $conf.HistoryPath = Join-Path $dataDir $conf.HistoryFile
    $conf.LogPath = Join-Path $logDir $conf.LogFile
    
    return $conf
}

# ============================================================
# 日志记录
# ============================================================
function Write-WaterLog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Level,
        
        [Parameter(Mandatory = $true)]
        [string]$Message
    )
    
    $conf = Get-Config
    $logDir = $conf.LogDir
    
    # 确保日志目录存在
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "$timestamp [$Level] $Message" | Add-Content -Path $conf.LogPath -Encoding UTF8
}

# ============================================================
# 天气感知 - 获取天气调整系数
# ============================================================
function Get-WeatherMultiplier {
    $conf = Get-Config
    
    if (-not $conf.WeatherEnabled) {
        return 1.0
    }
    
    try {
        # 使用 wttr.in 获取天气数据
        $weatherUrl = "https://wttr.in/?format=j1"
        $weatherData = Invoke-RestMethod -Uri $weatherUrl -TimeoutSec 5 -ErrorAction Stop
        $tempC = $weatherData.current_condition[0].temp_C
        
        # 根据温度计算调整系数
        if ($tempC -lt 15) {
            return 1.2    # 低温，延长间隔
        } elseif ($tempC -gt 35) {
            return 0.5    # 极端高温，大幅缩短
        } elseif ($tempC -gt 28) {
            return 0.7    # 高温，缩短间隔
        }
        
        return 1.0
    } catch {
        Write-WaterLog -Level 'WARN' -Message "天气获取失败: $($_.Exception.Message)"
        return 1.0
    }
}

# ============================================================
# 安静时段检测
# ============================================================
function Test-QuietHours {
    param([int]$Hour)
    
    $conf = Get-Config
    $start = $conf.QuietHoursStart
    $end = $conf.QuietHoursEnd
    
    # 处理跨午夜情况（如 22 点到 7 点）
    if ($start -gt $end) {
        return ($Hour -ge $start) -or ($Hour -lt $end)
    } else {
        return ($Hour -ge $start) -and ($Hour -lt $end)
    }
}

# ============================================================
# 获取下次活跃时间
# ============================================================
function Get-NextActiveTime {
    $conf = Get-Config
    $now = Get-Date
    $hour = $now.Hour
    $end = $conf.QuietHoursEnd
    
    if ($hour -lt $end) {
        return $now
    } else {
        return (Get-Date -Hour $end -Minute 0 -Second 0).AddDays(1)
    }
}

# ============================================================
# 生成时段感知文案
# ============================================================
function Get-TimeAwareMessage {
    param([int]$Hour)
    
    if ($Hour -lt 9) {
        return "早安！新的一天从一杯水开始~ (建议 250ml)"
    } elseif ($Hour -lt 12) {
        return "工作间隙，记得补充水分保持精力充沛！ (建议 250ml)"
    } elseif ($Hour -lt 14) {
        return "午餐前喝杯水，有助于控制食量哦~ (建议 300ml)"
    } elseif ($Hour -lt 17) {
        return "下午茶时间，水分补充不能少！ (建议 250ml)"
    } elseif ($Hour -lt 20) {
        return "傍晚时分，身体需要持续补水~ (建议 250ml)"
    } else {
        return "晚间放松，一杯温水帮助消化~ (建议 200ml)"
    }
}

# ============================================================
# 历史记录管理
# ============================================================
function Add-WaterRecord {
    param(
        [int]$Ml = 250
    )
    
    $conf = Get-Config
    $historyPath = $conf.HistoryPath
    $dataDir = $conf.DataDir
    $today = (Get-Date).ToString("yyyy-MM-dd")
    $now = (Get-Date).ToString("HH:mm")
    
    # 确保数据目录存在
    if (-not (Test-Path $dataDir)) {
        New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
    }
    
    $history = @{}
    
    # 读取现有历史记录
    if (Test-Path $historyPath) {
        try {
            $json = Get-Content $historyPath -Encoding UTF8 -Raw
            $history = ConvertFrom-Json -Json $json -AsHashtable -ErrorAction Stop
            if (-not ($history -is [hashtable])) {
                throw "Invalid history format"
            }
        } catch {
            Write-WaterLog -Level 'WARN' -Message "历史文件已损坏，已备份并重置: $historyPath"
            # 备份损坏的文件
            $backupPath = "$historyPath.bak.$(Get-Date -Format 'yyyyMMddHHmmss')"
            Copy-Item -Path $historyPath -Destination $backupPath -Force -ErrorAction SilentlyContinue
            $history = @{}
        }
    }
    
    # 使用 Mutex 防止并发写入
    $mutexName = "Global\WaterReminderHistory_$env:USERNAME"
    $mutex = $null
    try {
        $mutex = New-Object System.Threading.Mutex($false, $mutexName)
    } catch {
        # 回退到 Local 命名空间
        $mutexName = "Local\WaterReminderHistory_$env:USERNAME"
        try {
            $mutex = New-Object System.Threading.Mutex($false, $mutexName)
        } catch {
            # 最后回退到匿名 Mutex
            $mutex = New-Object System.Threading.Mutex($false)
        }
    }
    
    try {
        $mutex.WaitOne(5000) | Out-Null
        
        # 初始化当日记录
        if (-not $history.ContainsKey($today)) {
            $history[$today] = @{
                total   = 0
                records = @()
            }
        }
        
        # 添加新记录
        $history[$today].records += @{
            time = $now
            ml   = $Ml
        }
        $history[$today].total += $Ml
        
        # 保存历史记录
        $history | ConvertTo-Json -Depth 10 | Set-Content -Path $historyPath -Encoding UTF8
        
    } finally {
        $mutex.ReleaseMutex()
        $mutex.Dispose()
    }
    
    return @{
        Total        = $history[$today].total
        RecordsCount = $history[$today].records.Count
    }
}

function Get-WaterHistory {
    param([int]$Days = 7)
    
    $conf = Get-Config
    $historyPath = $conf.HistoryPath
    
    if (-not (Test-Path $historyPath)) {
        return $null
    }
    
    try {
        $json = Get-Content $historyPath -Encoding UTF8 -Raw
        return ConvertFrom-Json -Json $json -AsHashtable -ErrorAction Stop
    } catch {
        return $null
    }
}

function Get-WaterStatus {
    $conf = Get-Config
    $historyPath = $conf.HistoryPath
    $today = (Get-Date).ToString("yyyy-MM-dd")
    
    if (Test-Path $historyPath) {
        try {
            $json = Get-Content $historyPath -Encoding UTF8 -Raw
            $history = ConvertFrom-Json -Json $json -AsHashtable -ErrorAction Stop
            
            if ($history -and $history.ContainsKey($today)) {
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
        } catch {
            Write-WaterLog -Level 'WARN' -Message "读取状态失败: $($_.Exception.Message)"
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

# ============================================================
# 通知发送
# ============================================================
function Send-WaterNotification {
    param(
        [string]$Title = "💧 喝水提醒",
        [string]$Body = "该喝水了！",
        [int]$Interval = 60
    )
    
    $conf = Get-Config
    
    # 方案 1: Windows Toast 通知
    if (-not $IsWindows) {
        Write-WaterLog -Level 'WARN' -Message 'Toast notification not available on non-Windows'
        return $false
    }
    
    try {
        Add-Type -AssemblyName System.Runtime.WindowsRuntime -ErrorAction Stop
        $null = [Windows.UI.Notifications.ToastNotificationManager, Windows, ContentType = WindowsRuntime]
        
        $xml = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent(
            [Windows.UI.Notifications.ToastTemplateType]::ToastText02
        )
        $texts = $xml.GetElementsByTagName('text')
        $texts.Item(0).AppendChild($xml.CreateTextNode($Title)) | Out-Null
        $texts.Item(1).AppendChild($xml.CreateTextNode($Body)) | Out-Null
        
        $toast = [Windows.UI.Notifications.ToastNotification]::new($xml)
        $notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('PowerShellWaterReminder')
        $notifier.Show($toast)
        
        Write-WaterLog -Level 'INFO' -Message "Toast 通知已发送: $Title"
        return $true
    } catch {
        Write-WaterLog -Level 'WARN' -Message "Toast 通知失败: $($_.Exception.Message)"
    }
    
    # 方案 2: WinForms NotifyIcon
    if (-not [System.Environment]::UserInteractive) {
        Write-WaterLog -Level 'WARN' -Message 'WinForms 通知跳过: 非交互会话'
        return $false
    }
    
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
        
        $notify = New-Object System.Windows.Forms.NotifyIcon
        $notify.Icon = [System.Drawing.SystemIcons]::Information
        $notify.Visible = $true
        $notify.ShowBalloonTip(5000, $Title, $Body, [System.Windows.Forms.ToolTipIcon]::Info)
        
        Start-Sleep -Seconds 6
        $notify.Visible = $false
        $notify.Dispose()
        
        Write-WaterLog -Level 'INFO' -Message "WinForms 通知已发送: $Title"
        return $true
    } catch {
        Write-WaterLog -Level 'WARN' -Message "WinForms 通知失败: $($_.Exception.Message)"
    }
    
    # 方案 3: msg.exe 兜底
    try {
        $msgExe = Get-Command msg.exe -ErrorAction SilentlyContinue
        if ($msgExe) {
            # 移除 emoji 避免编码问题
            $cleanTitle = $Title -replace '[^\x20-\x7E\u4e00-\u9fff]', ''
            $cleanBody = $Body -replace '[^\x20-\x7E\u4e00-\u9fff]', ''
            $message = "$cleanTitle`r`n$cleanBody`r`n下次提醒: $Interval 分钟后"
            
            Start-Process -FilePath msg.exe -ArgumentList "/TIME:5", $env:USERNAME, $message -WindowStyle Hidden -ErrorAction SilentlyContinue
            Write-WaterLog -Level 'INFO' -Message "msg.exe 通知已发送: $Title"
            return $true
        }
    } catch {
        Write-WaterLog -Level 'ERROR' -Message "msg.exe 通知失败: $($_.Exception.Message)"
    }
    
    return $false
}

# ============================================================
# 核心提醒逻辑
# ============================================================
function Invoke-WaterReminder {
    [CmdletBinding()]
    param(
        [int]$DrinkMl = 250
    )
    
    $conf = Get-Config
    $hour = (Get-Date).Hour
    
    # 1. 获取天气调整系数
    $weatherMultiplier = Get-WeatherMultiplier
    
    # 2. 根据时段调整基础间隔
    $baseInterval = $conf.IntervalMin
    if ($hour -ge 11 -and $hour -lt 17) {
        $baseInterval = [Math]::Max(30, $baseInterval - 15)
    }
    
    $adjustedInterval = [int]($baseInterval * $weatherMultiplier)
    
    # 3. 生成时段感知文案
    $title = "💧 喝水提醒"
    $body = Get-TimeAwareMessage -Hour $hour
    
    if ($weatherMultiplier -lt 1.0) {
        $body += " [高温提醒：多补水]"
    }
    
    # 4. 记录历史数据
    $result = Add-WaterRecord -Ml $DrinkMl
    
    # 5. 检查是否超标
    $isOverGoal = $result.Total -gt $conf.DayGoalMl
    if ($isOverGoal) {
        $title = "🎉 今日目标已达成"
        $body = "今日已喝 $($result.Total)ml，超过了 $($conf.DayGoalMl)ml 的目标！继续加油~"
    }
    
    # 6. 发送通知
    Send-WaterNotification -Title $title -Body $body -Interval $adjustedInterval
    
    return @{
        Interval     = $adjustedInterval
        TotalToday   = $result.Total
        GoalProgress = [Math]::Round($result.Total / $conf.DayGoalMl * 100)
        RecordsCount = $result.RecordsCount
    }
}

# ============================================================
# 后台任务
# ============================================================
function Start-WaterReminderDaemon {
    [CmdletBinding()]
    param(
        [switch]$Background
    )
    
    $conf = Get-Config
    $pidFile = "$env:TEMP\.water-reminder.pid"
    
    if ($Background) {
        # 后台模式：写入 PID 并静默运行
        if ($null -ne $PID) {
            $PID | Set-Content -Path $pidFile -Encoding ASCII
        }
        
        try {
            while ($true) {
                $hour = (Get-Date).Hour
                
                # 安静时段则休眠
                if (Test-QuietHours -Hour $hour) {
                    Start-Sleep -Seconds 3600
                    continue
                }
                
                try {
                    $result = Invoke-WaterReminder
                    Write-WaterLog -Level 'INFO' -Message "喝水提醒已发送，今日进度: $($result.TotalToday)ml"
                    Start-Sleep -Seconds ($result.Interval * 60)
                } catch {
                    Write-WaterLog -Level 'ERROR' -Message $_.Exception.Message
                    Start-Sleep -Seconds 60
                }
            }
        } finally {
            if (Test-Path $pidFile) {
                Remove-Item -Path $pidFile -Force -ErrorAction SilentlyContinue
            }
        }
        return
    }
    
    # 前台交互模式
    Write-Host ""
    Write-Host "  💧 喝水提醒已启动 (Ctrl+C 停止)" -ForegroundColor Cyan
    Write-Host "  每日目标: $($conf.DayGoalMl) ml" -ForegroundColor DarkGray
    Write-Host "  基础间隔: $($conf.IntervalMin) 分钟" -ForegroundColor DarkGray
    
    $spinner = @('⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏')
    $spinnerIdx = 0
    
    while ($true) {
        try {
            $hour = (Get-Date).Hour
            
            # 检查安静时段
            if (Test-QuietHours -Hour $hour) {
                $nextActive = Get-NextActiveTime
                $waitSec = [int]($nextActive - (Get-Date)).TotalSeconds
                
                Write-Host ""
                Write-Host "  🌙 夜间休眠中，下次于 $($nextActive.ToString('HH:mm')) 提醒" -ForegroundColor DarkGray
                
                Start-Sleep -Seconds $waitSec
                continue
            }
            
            # 发送提醒
            $result = Invoke-WaterReminder
            
            Write-Host ""
            Write-Host "  ✓ 提醒已发送 | 今日进度: $($result.TotalToday) / $($conf.DayGoalMl) ml ($($result.GoalProgress)%)" -ForegroundColor Green
            
            # 倒计时显示
            $waitSeconds = $result.Interval * 60
            
            while ($waitSeconds -gt 0) {
                $mins = [int]($waitSeconds / 60)
                $secs = $waitSeconds % 60
                
                $spin = $spinner[$spinnerIdx % $spinner.Length]
                Write-Host "`r  ${spin} 下次提醒: ${mins}:$($secs.ToString('00'))  " -NoNewline -ForegroundColor DarkGray
                $spinnerIdx++
                Start-Sleep -Seconds 1
                $waitSeconds--
                
                # 每分钟检查安静时段
                if ($waitSeconds % 60 -eq 0 -and (Test-QuietHours -Hour (Get-Date).Hour)) {
                    Write-Host ""
                    break
                }
            }
            
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

function Stop-WaterReminderDaemon {
    $pidFile = "$env:TEMP\.water-reminder.pid"
    
    if (-not (Test-Path $pidFile)) {
        Write-Host " [!] 未检测到后台喝水提醒 PID 文件" -ForegroundColor Yellow
        return
    }
    
    $oldPid = Get-Content -Path $pidFile -Raw
    if ($oldPid -and (Get-Process -Id $oldPid -ErrorAction SilentlyContinue)) {
        try {
            Stop-Process -Id $oldPid -ErrorAction Stop
            Write-Host " [OK] 已停止后台喝水提醒 (PID: $oldPid)" -ForegroundColor Green
        } catch {
            Write-Host " [!] 无法停止 PID $oldPid，请手动检查进程" -ForegroundColor Yellow
        }
    } else {
        Write-Host " [!] 找不到正在运行的喝水提醒进程，已清除旧 PID 文件" -ForegroundColor Yellow
    }
    
    Remove-Item -Path $pidFile -Force -ErrorAction SilentlyContinue
}

function Get-WaterReminderStatus {
    $conf = Get-Config
    $stat = Get-WaterStatus
    $pidFile = "$env:TEMP\.water-reminder.pid"
    
    $bgStatus = @{ Running = $false; Pid = $null }
    if (Test-Path $pidFile) {
        $pid = (Get-Content -Path $pidFile -Raw).Trim()
        if ($pid -and (Get-Process -Id $pid -ErrorAction SilentlyContinue)) {
            $bgStatus = @{ Running = $true; Pid = $pid }
        }
    }
    
    $isQuiet = Test-QuietHours -Hour (Get-Date).Hour
    $nextActive = Get-NextActiveTime
    $nextActiveText = if ($isQuiet) { $nextActive.ToString('HH:mm') } else { '现在' }
    
    Write-Host ""
    Write-Host "  💧 喝水提醒状态"
    Write-Host "  ──────────────────────"
    Write-Host "  日期: $($stat.Date)"
    Write-Host "  今日摄入: $($stat.Total) / $($stat.Goal) ml"
    Write-Host "  目标进度: $($stat.Progress)%"
    Write-Host "  记录次数: $($stat.RecordsCount)"
    Write-Host "  后台服务: $(if ($bgStatus.Running) { "运行中 (PID: $($bgStatus.Pid))" } else { '未运行' })"
    Write-Host "  当前模式: $(if ($isQuiet) { '夜间静默' } else { '正常提醒' })"
    Write-Host "  下次可提醒: $nextActiveText"
    Write-Host ""
}

function Get-WaterReminderHistory {
    param(
        [int]$Days = 7
    )
    
    $conf = Get-Config
    $history = Get-WaterHistory -Days $Days
    
    if (-not $history) {
        Write-Host "  暂无历史记录" -ForegroundColor Yellow
        return
    }
    
    Write-Host ""
    Write-Host "  💧 喝水历史 (最近 ${Days} 天)"
    Write-Host "  ─────────────────────────────────────"
    
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

# ============================================================
# 导出模块成员
# ============================================================
Export-ModuleMember -Function @(
    'Invoke-WaterReminder'
    'Get-WaterStatus'
    'Get-WaterHistory'
    'Get-WeatherMultiplier'
    'Test-QuietHours'
    'Get-NextActiveTime'
    'Send-WaterNotification'
    'Start-WaterReminderDaemon'
    'Stop-WaterReminderDaemon'
    'Get-WaterReminderStatus'
    'Get-WaterReminderHistory'
)