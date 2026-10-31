# Get-TguiTerminalSize.ps1 - 解析仪表盘布局用的**真实终端尺寸**(纯读取)
#
# 背景 (2026-10-31 sss 仪表盘 UI 升级 · 真机取证):
#   旧实现只认两个来源: ScreenChanged 事件报数, 或 TG 的 Application.Screen。
#   在真实 TTY 上, Terminal.Gui 2.4.10 的 'ansi' 驱动在 **Init 之后、
#   事件循环跑起来之前** 报 0x0 —— 它要等终端回应 CSI 18t(查询窗口尺寸)
#   才把 Screen 填上, 而那个应答是异步到达的。实测(PTY 取证):
#       [Console]::WindowWidth = 120  (真实尺寸)
#       Application.Screen.Width = 0   (Init 后立即读)
#       ScreenChanged 事件: 只有在**收到按键**后才第一次报 120x35
#   于是"建窗那一刻"拿到的是 0x0 -> 编排层按兜底值 40x10 夹取 ->
#   列计划按 40 列算 -> **STATUS / WINDOWS 两列被判定为"窄屏隐藏"** ->
#   会话状态在界面上完全看不见(120 列的终端也只显示 # 与 SESSION 两列)。
#
#   本函数把"尺寸来源"收敛成一处, 并按可信度排序:
#     1) Event      —— ScreenChanged 事件报数(上一轮的真实尺寸, 最权威);
#     2) Console    —— [Console]::WindowWidth/Height(终端自己的尺寸,
#                     Init 前即可读, 不依赖 TG 的握手时序);
#     3) TguiScreen —— TG 的 Application.Screen(两者都拿不到时的兜底);
#     4) Fallback   —— 调用方给的缺省值。
#   注意"Console 在 TguiScreen 之前": 某些宿主下 TG 的 Screen 是**陈旧默认值**
#   (实测重定向容器里是 80x25), 而终端自己的尺寸才是用户看到的宽度。
#   两者不一致时, ScreenChanged 事件会在下一轮把尺寸对齐(编排层既有重建路径)。
#
# 契约: 只读, 不改任何状态; 返回 Width/Height/Source 供调用方记录来源。

function Get-TguiTerminalSize {
    <#
    .SYNOPSIS
        解析仪表盘布局用的终端尺寸(多来源兜底)。

    .DESCRIPTION
        按可信度依次尝试:
          1. $global:TguiScreenW / TguiScreenH(ScreenChanged 事件报数, >0 才算有效);
          2. [Console]::WindowWidth / WindowHeight(终端自身尺寸);
          3. Terminal.Gui 的 Application.Screen(宽度/高度均 >0 才算有效);
          4. -FallbackWidth / -FallbackHeight。
        最终结果按 -MinWidth / -MinHeight 夹取(仪表盘的最小可用尺寸)。

    .PARAMETER Tgui
        可选: Get-TguiContext 的返回值(避免重复拉起 ALC)。为空时内部自取。

    .PARAMETER FallbackWidth
        所有来源都拿不到时的缺省宽度(默认 120)。

    .PARAMETER FallbackHeight
        所有来源都拿不到时的缺省高度(默认 35)。

    .PARAMETER MinWidth
        宽度下限(默认 40, 与仪表盘的最小可用尺寸一致)。

    .PARAMETER MinHeight
        高度下限(默认 10)。

    .OUTPUTS
        [PSCustomObject] .Width / .Height / .Source('Event'|'Console'|'TguiScreen'|'Fallback')

    .EXAMPLE
        $size = Get-TguiTerminalSize
        $size.Width | Should -BeGreaterThan 0
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$Tgui,

        [Parameter(Mandatory = $false)]
        [ValidateRange(20, 1000)]
        [int]$FallbackWidth = 120,

        [Parameter(Mandatory = $false)]
        [ValidateRange(6, 1000)]
        [int]$FallbackHeight = 35,

        [Parameter(Mandatory = $false)]
        [ValidateRange(20, 1000)]
        [int]$MinWidth = 40,

        [Parameter(Mandatory = $false)]
        [ValidateRange(6, 1000)]
        [int]$MinHeight = 10
    )

    $width = 0
    $height = 0
    $source = ''

    # ---- 1) ScreenChanged 事件报数(上一轮的真实尺寸) ----
    if ($global:TguiScreenW -gt 0 -and $global:TguiScreenH -gt 0) {
        $width = [int]$global:TguiScreenW
        $height = [int]$global:TguiScreenH
        $source = 'Event'
    }

    # ---- 2) 终端自身尺寸(Init 之前即可读, 不依赖 TG 的 CSI 18t 握手) ----
    if ($width -le 0) {
        try {
            $consoleWidth = [int][Console]::WindowWidth
            $consoleHeight = [int][Console]::WindowHeight
            if ($consoleWidth -gt 0 -and $consoleHeight -gt 0) {
                $width = $consoleWidth
                $height = $consoleHeight
                $source = 'Console'
            }
        } catch {
            # 无控制台(重定向/服务宿主)时 Console 尺寸不可用 —— 继续下一档
            Write-Verbose "[Get-TguiTerminalSize] 读取控制台尺寸失败: $($_.Exception.Message)"
        }
    }

    # ---- 3) Terminal.Gui 的 Application.Screen ----
    if ($width -le 0) {
        try {
            $context = $Tgui
            if ($null -eq $context) { $context = Get-TguiContext }
            $screenProperty = $context.Types.Application.GetProperty('Screen', [System.Reflection.BindingFlags]'Public,Static')
            if ($null -ne $screenProperty) {
                $screen = $screenProperty.GetValue($null)
                if ($null -ne $screen) {
                    $screenWidth = [int]$screen.Width
                    $screenHeight = [int]$screen.Height
                    if ($screenWidth -gt 0 -and $screenHeight -gt 0) {
                        $width = $screenWidth
                        $height = $screenHeight
                        $source = 'TguiScreen'
                    }
                }
            }
        } catch {
            Write-Verbose "[Get-TguiTerminalSize] 读取 TG 屏幕尺寸失败: $($_.Exception.Message)"
        }
    }

    # ---- 4) 兜底 ----
    if ($width -le 0) {
        $width = $FallbackWidth
        $height = $FallbackHeight
        $source = 'Fallback'
    }

    if ($width -lt $MinWidth) { $width = $MinWidth }
    if ($height -lt $MinHeight) { $height = $MinHeight }

    return [PSCustomObject]@{
        Width  = $width
        Height = $height
        Source = $source
    }
}
