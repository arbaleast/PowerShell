# ============================================================
# TUIPerformanceState.ps1 - TUI 性能监控模块
# 遵循 ratatui 性能监控设计模式：滑动窗口 + FPS 计算
# ============================================================

# 性能状态类
class TUIPerformanceState {
    # 滑动窗口：存储时间戳用于 FPS 计算
    [System.Collections.Generic.Queue[TimeSpan]]$FrameTimestamps
    
    # 滑动窗口：存储每帧渲染时间（毫秒）
    [System.Collections.Generic.Queue[double]]$FrameTimes
    
    # 配置
    [int]$WindowSize = 60
    
    # 当前状态
    [DateTime]$LastFrameTime
    [double]$FPS
    [double]$AvgFrameTime
    [double]$PeakFrameTime
    [double]$MinFrameTime
    [int]$TotalFrames
    
    # 事件统计
    [int]$KeyPressCount
    [int]$RenderCount
    [DateTime]$SessionStartTime
    
    TUIPerformanceState() {
        $this.FrameTimestamps = [System.Collections.Generic.Queue[TimeSpan]]::new()
        $this.FrameTimes = [System.Collections.Generic.Queue[double]]::new()
        $this.WindowSize = 60
        $this.LastFrameTime = [DateTime]::UtcNow
        $this.SessionStartTime = [DateTime]::UtcNow
        $this.TotalFrames = 0
        $this.KeyPressCount = 0
        $this.RenderCount = 0
        $this.FPS = 0.0
        $this.AvgFrameTime = 0.0
        $this.PeakFrameTime = 0.0
        $this.MinFrameTime = [double]::MaxValue
        # P5 缓存摘要
        $this._cachedSummary = $null
        $this._summaryDirty = $true
    }
    
    # P5 缓存字段
    hidden [hashtable]$_cachedSummary
    hidden [bool]$_summaryDirty
    
    # 报告新帧完成
    [void] ReportFrame() {
        $now = [DateTime]::UtcNow
        $delta = $now - $this.LastFrameTime
        $this.LastFrameTime = $now
        
        $deltaMs = $delta.TotalMilliseconds
        
        # 更新帧时间队列
        $this.FrameTimes.Enqueue($deltaMs)
        if ($this.FrameTimes.Count -gt $this.WindowSize) {
            # P5 优化：使用 [void] 替代管道 Out-Null
            [void]$this.FrameTimes.Dequeue()
        }
        
        # 更新时间戳队列（用于 FPS 计算）
        $this.FrameTimestamps.Enqueue($now.TimeOfDay)
        if ($this.FrameTimestamps.Count -gt $this.WindowSize) {
            # P5 优化：使用 [void] 替代管道 Out-Null
            [void]$this.FrameTimestamps.Dequeue()
        }
        
        $this.TotalFrames++
        $this.RenderCount++
        
        # P5 优化：数据变更时标记缓存为脏
        $this._summaryDirty = $true
        
        # 计算统计数据
        $this.CalculateFPS()
        $this.CalculateFrameTimeStats()
    }
    
    # 报告按键事件
    [void] ReportKeyPress() {
        $this.KeyPressCount++
    }
    
    # 计算 FPS（滑动窗口算法）
    [void] CalculateFPS() {
        if ($this.FrameTimestamps.Count -lt 2) { 
            $this.FPS = 0.0
            return 
        }
        
        $first = $this.FrameTimestamps.First()
        $last = $this.FrameTimestamps.Last()
        $durationSec = ($last - $first).TotalSeconds
        
        if ($durationSec -gt 0) {
            $this.FPS = ($this.FrameTimestamps.Count - 1) / $durationSec
        }
    }
    
    # 计算帧时间统计
    [void] CalculateFrameTimeStats() {
        if ($this.FrameTimes.Count -eq 0) { return }
        
        $sum = 0.0
        $peak = 0.0
        $min = [double]::MaxValue
        
        foreach ($ft in $this.FrameTimes) {
            $sum += $ft
            if ($ft -gt $peak) { $peak = $ft }
            if ($ft -lt $min) { $min = $ft }
        }
        
        $this.AvgFrameTime = $sum / $this.FrameTimes.Count
        $this.PeakFrameTime = $peak
        $this.MinFrameTime = $min
    }
    
    # 获取性能摘要
    [hashtable] GetSummary() {
        $uptime = [DateTime]::UtcNow - $this.SessionStartTime
        
        return @{
            FPS           = [math]::Round($this.FPS, 1)
            AvgFrameTime  = [math]::Round($this.AvgFrameTime, 2)
            PeakFrameTime = [math]::Round($this.PeakFrameTime, 2)
            MinFrameTime  = [math]::Round($this.MinFrameTime, 2)
            TotalFrames   = $this.TotalFrames
            KeyPressCount = $this.KeyPressCount
            RenderCount   = $this.RenderCount
            UptimeSeconds = [math]::Round($uptime.TotalSeconds, 0)
            IsHealthy     = ($this.FPS -gt 0 -and $this.FPS -lt 120)
        }
    }
    
    # 重置统计
    [void] Reset() {
        $this.FrameTimestamps.Clear()
        $this.FrameTimes.Clear()
        $this.LastFrameTime = [DateTime]::UtcNow
        $this.SessionStartTime = [DateTime]::UtcNow
        $this.TotalFrames = 0
        $this.KeyPressCount = 0
        $this.RenderCount = 0
        $this.FPS = 0.0
        $this.AvgFrameTime = 0.0
        $this.PeakFrameTime = 0.0
        $this.MinFrameTime = [double]::MaxValue
    }
}

# 全局性能状态实例
$Global:TUI_PerfState = $null

# 初始化性能监控
function Initialize-TUIPerformance {
    <#
    .SYNOPSIS
    初始化全局性能状态
    #>
    
    if ($null -eq $Global:TUI_PerfState) {
        $Global:TUI_PerfState = [TUIPerformanceState]::new()
    }
    
    return $Global:TUI_PerfState
}

# 便捷访问函数
function Get-TUIPerformance {
    <#
    .SYNOPSIS
    获取当前性能状态
    #>
    
    if ($null -eq $Global:TUI_PerfState) {
        Initialize-TUIPerformance | Out-Null
    }
    
    return $Global:TUI_PerfState.GetSummary()
}

function Measure-TUIFrame {
    <#
    .SYNOPSIS
    报告一帧完成，用于性能监控
    #>
    
    if ($null -eq $Global:TUI_PerfState) {
        Initialize-TUIPerformance | Out-Null
    }
    
    $Global:TUI_PerfState.ReportFrame()
}

function Measure-TUIKeyPress {
    <#
    .SYNOPSIS
    报告一次按键事件
    #>
    
    if ($null -ne $Global:TUI_PerfState) {
        $Global:TUI_PerfState.ReportKeyPress()
    }
}

# 渲染调试覆盖层
function Show-TUIDebugOverlay {
    <#
    .SYNOPSIS
    在终端左上角渲染性能调试覆盖层
    #>
    
    param(
        [int]$Width = 40,
        [int]$OffsetTop = 0
    )
    
    if ($null -eq $Global:TUI_PerfState) { return }
    
    $perf = $Global:TUI_PerfState.GetSummary()
    
    # 构建调试信息
    $lines = @()
    $lines += "┌$('─' * ($Width - 2))┐"
    $lines += "│ DEBUG OVERLAY".PadRight($Width - 1) + "│"
    $lines += "├$('─' * ($Width - 2))┤"
    $lines += "│ FPS: $($perf.FPS)  Frame: $($perf.AvgFrameTime)ms".PadRight($Width - 1) + "│"
    $lines += "│ Peak: $($perf.PeakFrameTime)ms  Min: $($perf.MinFrameTime)ms".PadRight($Width - 1) + "│"
    $lines += "│ Frames: $($perf.TotalFrames)  Keys: $($perf.KeyPressCount)".PadRight($Width - 1) + "│"
    $lines += "│ Uptime: $($perf.UptimeSeconds)s".PadRight($Width - 1) + "│"
    $lines += "└$('─' * ($Width - 2))┘"
    
    # 保存当前光标位置
    $origTop = [Console]::CursorTop
    $origLeft = [Console]::CursorLeft
    
    # 渲染调试覆盖层
    [Console]::SetCursorPosition(0, $OffsetTop)
    foreach ($line in $lines) {
        Write-Host $line -ForegroundColor Yellow
    }
    
    # 恢复光标位置
    [Console]::SetCursorPosition($origLeft, $origTop)
}

# 导出模块成员