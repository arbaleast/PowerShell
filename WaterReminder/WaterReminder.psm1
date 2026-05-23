# ============================================================
# WaterReminder.psm1 - 喝水提醒核心模块
# 包含：天气感知、时段文案、历史记录、通知发送
# ============================================================

# 加载配置
$script:Config = & (Join-Path $PSScriptRoot 'config.ps1')

# ============================================================
# 模块级状态变量（在模块加载时初始化一次，避免每次检查注册表）
# ============================================================

# AppUserModelID - Windows Toast 通知的应用标识符
$script:AppUserModelId = 'WaterReminder'

# 通知系统状态标志
$script:ToastInitialized = $false   # Toast 通知系统是否已完成初始化
$script:BurntToastAvailable = $null # BurntToast 模块可用性缓存（$null=未检测）
$script:AppIdRegistered = $false    # AppUserModelID 是否已注册

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
# AppUserModelID 注册（Windows Toast 通知必需）
# ============================================================

<#
.SYNOPSIS
  注册 AppUserModelID 到 HKCU 注册表，使 Windows Toast 通知可用
.DESCRIPTION
  在模块加载时调用一次。将当前 $script:AppUserModelId 写入注册表，
  并设置 DisplayName 和 IconUri。如果注册失败（如权限不足），
  不会抛出终止异常，而是记录警告并返回 $false。
#>
function Register-AppUserModelID {
    [CmdletBinding()]
    param()

    # 仅在 Windows 上执行
    if (-not $IsWindows) {
        Write-WaterLog -Level 'DEBUG' -Message "AppUserModelID 注册跳过: 非 Windows 平台"
        return $false
    }

    try {
        # AppUserModelID 注册表路径
        $regPath = "HKCU:\Software\Classes\AppUserModelId\$script:AppUserModelId"

        # 检查是否已注册
        if (Test-Path $regPath) {
            Write-WaterLog -Level 'DEBUG' -Message "AppUserModelID 已注册: $script:AppUserModelId"
            $script:AppIdRegistered = $true
            return $true
        }

        # 创建注册表项
        $null = New-Item -Path $regPath -Force -ErrorAction Stop

        # 设置 DisplayName
        $null = New-ItemProperty -Path $regPath -Name 'DisplayName' -PropertyType String `
            -Value '饮水提醒' -Force -ErrorAction Stop

        # 设置 IconUri（使用系统图标作为 fallback）
        $iconUri = "%SystemRoot%\System32\notepad.exe,0"
        $null = New-ItemProperty -Path $regPath -Name 'IconUri' -PropertyType String `
            -Value $iconUri -Force -ErrorAction Stop

        # 设置 ShowInSettings（在系统通知设置中可见）
        $null = New-ItemProperty -Path $regPath -Name 'ShowInSettings' -PropertyType DWord `
            -Value 1 -Force -ErrorAction SilentlyContinue

        $script:AppIdRegistered = $true
        Write-WaterLog -Level 'INFO' -Message "AppUserModelID 已注册: $script:AppUserModelId"
        return $true

    } catch {
        # 注册失败不抛出异常，通知会自动降级
        Write-WaterLog -Level 'WARN' -Message "AppUserModelID 注册失败: $($_.Exception.Message)"
        $script:AppIdRegistered = $false
        return $false
    }
}

# ============================================================
# BurntToast 模块可用性检测
# ============================================================

<#
.SYNOPSIS
  检测 BurntToast PowerShell 模块是否已安装
.DESCRIPTION
  通过 Get-Module -ListAvailable 检查 BurntToast 模块是否存在。
  结果缓存到 $script:BurntToastAvailable，避免每次通知都重复检查。
#>
function Test-BurntToastAvailable {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    # 如果已缓存结果，直接返回
    if ($null -ne $script:BurntToastAvailable) {
        return $script:BurntToastAvailable
    }

    try {
        $module = Get-Module -ListAvailable -Name 'BurntToast' -ErrorAction SilentlyContinue
        $available = ($null -ne $module)
        $script:BurntToastAvailable = $available
        if (-not $available) {
            Write-WaterLog -Level 'DEBUG' -Message "BurntToast 模块未安装，跳过 BurntToast 通知"
        }
        return $available
    } catch {
        $script:BurntToastAvailable = $false
        return $false
    }
}

# ============================================================
# 通知发送（三级回退机制）
# ============================================================

<#
.SYNOPSIS
  发送喝水提醒通知，包含三级回退机制
.DESCRIPTION
  优先级:
    1级 - BurntToast 通知（功能最丰富，需要安装 BurntToast 模块）
    2级 - 原生 Windows Toast 通知（需要 AppUserModelID 注册）
    3级 - 控制台彩色输出（最可靠的 fallback）
  全部失败后落日志记录。
#>
function Send-WaterNotification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Title = "💧 喝水提醒",

        [Parameter(Mandatory = $false)]
        [string]$Body = "该喝水了！",

        [Parameter(Mandatory = $false)]
        [int]$Interval = 60
    )

    $conf = Get-Config

    # ---- 非 Windows 平台：直接降级到控制台输出 ----
    if (-not $IsWindows) {
        Write-WaterLog -Level 'WARN' -Message "Windows 通知在非 Windows 平台不可用，降级到控制台输出"
        _Send-ConsoleNotification -Title $Title -Body $Body
        return $false
    }

    # ============================================================
    # 1级通知：BurntToast 通知（需要安装 BurntToast 模块）
    # ============================================================
    if (-not (Test-BurntToastAvailable)) {
        Write-WaterLog -Level 'DEBUG' -Message "1级 BurntToast 跳过: 模块未安装。如需使用，请执行: Install-Module BurntToast"
    } else {
        try {
            # BurntToast 模块已加载，直接发送通知
            # New-BurntToastNotification 会自动处理 AppUserModelID
            $null = Import-Module BurntToast -Force -ErrorAction Stop
            New-BurntToastNotification -AppLogo $null `
                -Text $Title, $Body `
                -AppId $script:AppUserModelId `
                -ErrorAction Stop | Out-Null

            Write-WaterLog -Level 'INFO' -Message "1级 BurntToast 通知已发送: $Title"
            return $true
        } catch {
            Write-WaterLog -Level 'WARN' -Message "1级 BurntToast 通知失败: $($_.Exception.Message)，降级到 2级"
        }
    }

    # ============================================================
    # 2级通知：原生 Windows Toast 通知（利用 Windows Runtime API）
    # ============================================================
    # 在首次发送前确保 AppUserModelID 已注册
    if (-not $script:AppIdRegistered) {
        Write-WaterLog -Level 'DEBUG' -Message "2级 Toast 前检查: AppUserModelID 未注册，尝试注册"
        $null = Register-AppUserModelID
    }

    if ($script:AppIdRegistered) {
        try {
            # 加载 Windows Runtime 类型
            Add-Type -AssemblyName System.Runtime.WindowsRuntime -ErrorAction Stop
            $null = [Windows.UI.Notifications.ToastNotificationManager, Windows, ContentType = WindowsRuntime]

            # 创建 Toast XML 模板（ToastText02 = 标题 + 正文两行）
            $xml = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent(
                [Windows.UI.Notifications.ToastTemplateType]::ToastText02
            )
            $texts = $xml.GetElementsByTagName('text')
            $texts.Item(0).AppendChild($xml.CreateTextNode($Title)) | Out-Null
            $texts.Item(1).AppendChild($xml.CreateTextNode($Body)) | Out-Null

            # 使用已注册的 AppUserModelID 创建通知器
            $toast = [Windows.UI.Notifications.ToastNotification]::new($xml)
            $notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($script:AppUserModelId)
            $notifier.Show($toast)

            Write-WaterLog -Level 'INFO' -Message "2级 Toast 通知已发送: $Title"
            return $true
        } catch {
            Write-WaterLog -Level 'WARN' -Message "2级 Toast 通知失败: $($_.Exception.Message)，降级到 3级"
        }
    }

    # ============================================================
    # 3级通知：控制台彩色输出 + 弹窗提示
    # ============================================================
    try {
        _Send-ConsoleNotification -Title $Title -Body $Body -Interval $Interval
        Write-WaterLog -Level 'INFO' -Message "3级 控制台通知已发送: $Title"
        return $true
    } catch {
        Write-WaterLog -Level 'ERROR' -Message "3级 控制台通知失败: $($_.Exception.Message)"
    }

    # ============================================================
    # 全部失败：记录到日志
    # ============================================================
    Write-WaterLog -Level 'ERROR' -Message "全部通知方式均失败，仅记录日志: $Title - $Body"
    return $false
}

# ============================================================
# 内部辅助函数：控制台通知
# ============================================================
function _Send-ConsoleNotification {
    [CmdletBinding()]
    param(
        [string]$Title,
        [string]$Body,
        [int]$Interval = 0
    )

    # 彩色控制台输出
    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║        💧 喝水提醒                   ║" -ForegroundColor Cyan
    Write-Host "  ╠══════════════════════════════════════╣" -ForegroundColor Cyan
    Write-Host "  ║  $($Title.PadRight(35))║" -ForegroundColor White
    Write-Host "  ║                                      ║" -ForegroundColor Cyan
    Write-Host "  ║  $($Body.PadRight(35))║" -ForegroundColor Yellow
    Write-Host "  ║                                      ║" -ForegroundColor Cyan
    if ($Interval -gt 0) {
        Write-Host "  ║  下次提醒: ${Interval} 分钟后           ║" -ForegroundColor DarkGray
        Write-Host "  ║                                      ║" -ForegroundColor Cyan
    }
    Write-Host "  ╚══════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""

    # 尝试使用 MessageBox 弹窗（可能在非交互式会话失败）
    try {
        if ([System.Environment]::UserInteractive) {
            Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
            $null = [System.Windows.Forms.MessageBox]::Show($Body, $Title,
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information)
        }
    } catch {
        # MessageBox 弹窗失败不影响主流程
        Write-WaterLog -Level 'DEBUG' -Message "MessageBox 弹窗跳过: $($_.Exception.Message)"
    }
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
# 模块初始化（仅在模块加载时执行一次）
# ============================================================

# 在模块加载时尝试注册 AppUserModelID，结果缓存到 $script:AppIdRegistered
# 这样后续每次发送通知时不需要再检查注册表
if ($IsWindows) {
    $null = Register-AppUserModelID

    # 检查 BurntToast 模块是否已安装（缓存结果）
    $null = Test-BurntToastAvailable

    # 输出初始化状态（仅在前台模式下显示）
    if (-not $script:AppIdRegistered) {
        Write-WaterLog -Level 'INFO' -Message "AppUserModelID 未注册，Toast 通知将自动降级到控制台输出"
    }
    if (-not $script:BurntToastAvailable) {
        Write-WaterLog -Level 'DEBUG' -Message "BurntToast 模块未安装，如需更丰富的通知体验请执行: Install-Module BurntToast"
    }
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