# ============================================================
# TUIPerformanceState.ps1 - TUI 性能监控模块
# 遵循 ratatui 性能监控设计模式：滑动窗口 + FPS 计算
# 优化: 增量 O(1) 统计（避免每帧 O(n) 遍历队列）
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

    # P5 缓存字段
    hidden [hashtable]$_cachedSummary
    hidden [bool]$_summaryDirty

    # 算法优化：增量 O(1) 帧时间统计（替代 O(n) foreach）
    # 维护当前窗口内的 sum/count/peak/min，新帧入队时 O(1) 更新，
    # 旧帧出队时若为 peak/min 则降级为重新扫描（均摊仍为 O(1)）。
    hidden [double]$_sum
    hidden [int]$_count

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
        $this._cachedSummary = $null
        $this._summaryDirty = $true
        $this._sum = 0.0
        $this._count = 0
    }

    # 报告新帧完成
    [void] ReportFrame() {
        $now = [DateTime]::UtcNow
        $delta = $now - $this.LastFrameTime
        $this.LastFrameTime = $now

        $deltaMs = $delta.TotalMilliseconds

        # 算法优化: 维护窗口大小限制 + 增量更新 sum/count/peak/min
        # 出队仅在窗口已满时发生
        if ($this.FrameTimes.Count -ge $this.WindowSize) {
            $removed = $this.FrameTimes.Dequeue()
            $this._sum -= $removed
            $this._count--
            # 若被淘汰的是峰值/谷值，标记脏（由 GetSummary 重建）
            # 为简化处理：仅在出队后 Peak/Min 仍可达时按需重建
            if ($removed -eq $this.PeakFrameTime) { $this._RecalculatePeakMin() }
            if ($removed -eq $this.MinFrameTime) { $this._RecalculatePeakMin() }
        }

        $this.FrameTimes.Enqueue($deltaMs)
        $this._sum += $deltaMs
        $this._count++

        # O(1) 更新 peak/min
        if ($deltaMs -gt $this.PeakFrameTime) { $this.PeakFrameTime = $deltaMs }
        if ($deltaMs -lt $this.MinFrameTime) { $this.MinFrameTime = $deltaMs }

        # 更新时间戳队列（用于 FPS 计算）
        $this.FrameTimestamps.Enqueue($now.TimeOfDay)
        if ($this.FrameTimestamps.Count -gt $this.WindowSize) {
            [void]$this.FrameTimestamps.Dequeue()
        }

        # O(1) 更新平均帧时间
        $this.AvgFrameTime = if ($this._count -gt 0) { $this._sum / $this._count } else { 0.0 }

        $this.TotalFrames++
        $this.RenderCount++

        # 标记缓存为脏
        $this._summaryDirty = $true

        # 计算 FPS（O(1) 仅取首尾时间戳）
        $this.CalculateFPS()
    }

    # 报告按键事件
    [void] ReportKeyPress() {
        $this.KeyPressCount++
    }

    # 计算 FPS（O(1) 滑动窗口算法）
    [void] CalculateFPS() {
        if ($this.FrameTimestamps.Count -lt 2) {
            $this.FPS = 0.0
            return
        }

        # Queue<T>.First() / .Last() 在 .NET 上为 O(1)
        $first = $this.FrameTimestamps.First()
        $last = $this.FrameTimestamps.Last()
        $durationSec = ($last - $first).TotalSeconds

        if ($durationSec -gt 0) {
            $this.FPS = ($this.FrameTimestamps.Count - 1) / $durationSec
        }
    }

    # 内部：出队时若 peak/min 被淘汰，重新扫描（仅在边缘情况触发）
    hidden [void] _RecalculatePeakMin() {
        if ($this.FrameTimes.Count -eq 0) {
            $this.PeakFrameTime = 0.0
            $this.MinFrameTime = [double]::MaxValue
            return
        }
        $peak = 0.0
        $min = [double]::MaxValue
        foreach ($ft in $this.FrameTimes) {
            if ($ft -gt $peak) { $peak = $ft }
            if ($ft -lt $min) { $min = $ft }
        }
        $this.PeakFrameTime = $peak
        $this.MinFrameTime = $min
    }

    # 获取性能摘要（O(1) 缓存版本）
    [hashtable] GetSummary() {
        if ($this._summaryDirty -or $null -eq $this._cachedSummary) {
            $uptime = [DateTime]::UtcNow - $this.SessionStartTime
            $this._cachedSummary = @{
                FPS           = [math]::Round($this.FPS, 1)
                AvgFrameTime  = [math]::Round($this.AvgFrameTime, 2)
                PeakFrameTime = [math]::Round($this.PeakFrameTime, 2)
                MinFrameTime  = if ($this.MinFrameTime -eq [double]::MaxValue) { 0.0 } else { [math]::Round($this.MinFrameTime, 2) }
                TotalFrames   = $this.TotalFrames
                KeyPressCount = $this.KeyPressCount
                RenderCount   = $this.RenderCount
                UptimeSeconds = [math]::Round($uptime.TotalSeconds, 0)
                IsHealthy     = ($this.FPS -gt 0 -and $this.FPS -lt 120)
            }
            $this._summaryDirty = $false
        }
        return $this._cachedSummary
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
        $this._sum = 0.0
        $this._count = 0
        $this._summaryDirty = $true
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
