# New-TmuxTuiColumnPlan.ps1 - TGUI 会话表格的**列布局计划**(纯函数, 阶段 A 视图层)
#
# 背景 (2026-10-30 TGUI 迁移 · 阶段 A 视图层):
#   Goal 三-2/3-5: 列 #(序号)/SESSION(优先空间)/STATUS/WINDOWS(右对齐);
#   窄窗口隐藏次要列(STATUS), 不允许横向溢出 —— 100x30/120x35/160x45 三档。
#   布局计算与 TG 组装解耦: 本函数只产计划(纯数据), 由 New-TmuxTuiSessionTable
#   消费(建 EnumeratorTableSource + ColumnStyle)。
#
# 列宽模型 (Terminal.Gui 2.4.10 实测: ColumnStyle.HasKey Width 三件套:
#   MinWidth / MinAcceptableWidth / MaxWidth; TableStyle.ColumnStyles
#   = Dictionary<int, ColumnStyle>(按列序号键)):
#   宽度档位(终端列数):
#     >= 160: STATUS 显示, SESSION 最宽
#     >= 120: STATUS 显示, SESSION 收窄
#     >=  96: STATUS 显示(最小宽度), SESSION 中等
#      <  96: STATUS 隐藏(窄窗口隐藏次要信息)
#     <   72: WINDOWS 隐藏(超窄, 只有 # + SESSION)

function New-TmuxTuiColumnPlan {
    <#
    .SYNOPSIS
        按终端窗口宽度生成会话表格的列布局计划(纯函数)。

    .DESCRIPTION
        返回 PSCustomObject 数组, 顺序即列序:
            {No}      固定宽度   4
            {SESSION} 会话名, 其余空间优先给它(权重最小 MinWidth)
            {STATUS}  10 宽, Alignment 居中; 终端 <96 列时 Visible=$false
            {WINDOWS} 9 宽, RightAlign=$true(数值右对齐); 终端 <72 列隐藏
        每项字段: Name / MinWidth / MaxWidth / RightAlign / Visible。

        对应 Goal 100x30/120x35/160x45 验证档; 缺省 $WindowWidth = 120。

    .PARAMETER WindowWidth
        终端可用列数([Console]::WindowWidth), 测试可注入任意值。

    .OUTPUTS
        [PSCustomObject[]] 列计划(No/SESSION/STATUS/WINDOWS, 带 Visible/宽度域)

    .EXAMPLE
        $plan = New-TmuxTuiColumnPlan -WindowWidth 100
        ($plan | Where-Object Name -eq 'STATUS').Visible | Should -BeFalse
    #>
    # 纯函数, 不改系统状态 —— New- 动词按 PSSA 规则需显式豁免 ShouldProcess
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory = $false)]
        [ValidateRange(40, 1000)]
        [int]$WindowWidth = 120
    )

    $showStatus = $WindowWidth -ge 96
    $showWindows = $WindowWidth -ge 72

    # SESSION 宽度: 终端越宽给越多; MaxWidth 广度覆盖 160 列横幅
    $sessionMin = 12
    $sessionMax = if ($WindowWidth -ge 160) { 80 } elseif ($WindowWidth -ge 120) { 60 } else { 40 }

    return @(
        [PSCustomObject]@{ Name = 'No';      MinWidth = 4;  MaxWidth = 4;            RightAlign = $false; Visible = $true }
        [PSCustomObject]@{ Name = 'SESSION'; MinWidth = $sessionMin; MaxWidth = $sessionMax; RightAlign = $false; Visible = $true }
        [PSCustomObject]@{ Name = 'STATUS';  MinWidth = 10; MaxWidth = 10;           RightAlign = $false; Visible = $showStatus }
        [PSCustomObject]@{ Name = 'WINDOWS'; MinWidth = 9;  MaxWidth = 9;            RightAlign = $true;  Visible = $showWindows }
    )
}
