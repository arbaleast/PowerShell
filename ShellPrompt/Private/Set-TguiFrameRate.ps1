# Set-TguiFrameRate.ps1 - 调整 Terminal.Gui 主循环的帧率上限(实测的延迟地板)
#
# 背景 (2026-11-01 实测):
#   `sss` 的两个仪表盘在真机(Windows Terminal)上, 上下移动选中仍有 **100~200ms**
#   的延迟, 且**把重绘面积缩小 5~12 倍之后延迟几乎没变** —— 这说明瓶颈不在
#   "这一帧画多少", 而在"多久才画下一帧"。
#
#   直接测得的事实(Terminal.Gui 2.4.10, vendored):
#     Application.DefaultMaximumIterationsPerSecond = 25
#   即主循环**每秒最多转 25 圈** ⇒ 相邻两帧之间有 **1000/25 = 40ms** 的
#   硬地板。按键必须等下一帧才能出画面, 于是"按键 -> 画面"的延迟下限就是
#   这一帧的周期; 在慢机器 / 宽终端 / 重帧上, 40ms 会被拉长到 100~200ms ——
#   **与脏区大小无关**, 所以缩小脏区治不了它。
#
#   `Application.MaximumIterationsPerSecond` 是 **public static 可写属性**
#   (2.4.10 实测), 是唯一一根针对这个地板的官方杠杆。
#
# 设计取舍:
#   - 只**调高**, 不调低(用户/环境已经调高过就不动它);
#   - 取值 100 => 帧周期 10ms。TG 的主循环在无重绘时只是 sleep + 检查,
#     空闲开销可忽略; 有重绘时才真正干活, 所以这是"低延迟"与"CPU"之间的
#     合理折中。
#   - **不改** TG 的其它时序语义(不影响备用屏/事件循环/Resize 行为)。

function Set-TguiFrameRate {
    <#
    .SYNOPSIS
        把 Terminal.Gui 主循环的帧率上限调到不低于指定值(只调高)。

    .DESCRIPTION
        主循环帧率决定"按键 -> 画面更新"的地板: 默认 25 fps ⇒ 40ms 一帧。
        本函数把 `Application.MaximumIterationsPerSecond` 抬到 `MinimumIps`
        (默认 100 => 10ms 一帧), 已经高于该值时**不动**(尊重既有设置)。

        调用时机: **Application.Init 之后**、进入事件循环之前。

    .PARAMETER Tgui
        Get-TguiContext 的上下文对象(提供 ALC 内类型句柄)。

    .PARAMETER MinimumIps
        期望的最小帧率(默认 100)。

    .OUTPUTS
        [PSCustomObject] .Previous / .Current / .Applied —— 便于诊断与日志。

    .EXAMPLE
        Set-TguiFrameRate -Tgui (Get-TguiContext)
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Tgui,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 1000)]
        [int]$MinimumIps = 100
    )

    $appType = $Tgui.Types.Application
    $prop = $appType.GetProperty('MaximumIterationsPerSecond',
        [System.Reflection.BindingFlags]'Public,Static')
    if ($null -eq $prop) {
        Write-Verbose '[Set-TguiFrameRate] 当前 TG 没有 MaximumIterationsPerSecond 属性, 跳过。'
        return [PSCustomObject]@{ Previous = 0; Current = 0; Applied = $false }
    }

    $previous = 0
    try { $previous = [int]$prop.GetValue($null) } catch { $previous = 0 }
    if ($previous -ge $MinimumIps) {
        # 已经是想要的(或更高的)帧率 —— 不动它。
        return [PSCustomObject]@{ Previous = $previous; Current = $previous; Applied = $false }
    }

    try {
        $prop.SetValue($null, [uint16]$MinimumIps)
        $current = [int]$prop.GetValue($null)
        Write-Verbose "[Set-TguiFrameRate] 主循环帧率上限 $previous -> $current fps(帧周期 $([Math]::Round(1000.0 / [Math]::Max(1, $current), 1))ms)"
        return [PSCustomObject]@{ Previous = $previous; Current = $current; Applied = $true }
    }
    catch {
        Write-Verbose "[Set-TguiFrameRate] 设置帧率失败: $($_.Exception.Message)"
        return [PSCustomObject]@{ Previous = $previous; Current = $previous; Applied = $false }
    }
}
