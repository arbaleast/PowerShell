# New-TmuxTuiColumnPlan.ps1 - TGUI 会话表格的**列布局计划**(纯函数, 阶段 A 视图层)
#
# 背景 (2026-10-30 TGUI 迁移 · 阶段 A 视图层):
#   Goal 三-2/3-5: 列 #(序号)/SESSION(优先空间)/STATUS/WINDOWS(右对齐);
#   窄窗口隐藏次要列(STATUS), 不允许横向溢出 —— 100x30/120x35/160x45 三档。
#   布局计算与 TG 组装解耦: 本函数只产计划(纯数据), 由 New-TmuxTuiSessionTable
#   消费(建 EnumeratorTableSource + ColumnStyle)。
#
# 列宽模型 (Terminal.Gui 2.4.10 实测: ColumnStyle 有 Width 三件套:
#   MinWidth / MinAcceptableWidth / MaxWidth; TableStyle.ColumnStyles
#   = Dictionary<int, ColumnStyle>(按列序号键)):
#   宽度档位(终端列数):
#     >= 160: STATUS 显示, SESSION 最宽
#     >= 120: STATUS 显示, SESSION 收窄
#     >=  96: STATUS 显示(最小宽度), SESSION 中等
#      <  96: STATUS 隐藏(窄窗口隐藏次要信息)
#     <   72: WINDOWS 隐藏(超窄, 只有 # + SESSION)
#
# ★ 2026-10-31 UI 升级: SESSION 改成**吃满剩余宽度**(Min=Max=余量)。
#   旧模型给 SESSION 一个封顶宽度(40/60/80), 其余空间留在表格框里:
#     - 若最后一列(WINDOWS)被 TG 拉伸, 它会变成一个几十列宽的空洞;
#     - 若不拉伸, 表格框右侧留下一大片空白, 看起来像渲染坏了。
#   真机取证(120 列): 旧实现只显示 #/SESSION 两列(列计划按 40 列算, 见
#   Get-TguiTerminalSize 的说明), 且 SESSION 列被拉伸到 33 列却只有 8 个字符。
#   现在按**实测的表格几何**精确分配:
#       表格总宽 = Σ(各列宽) + (可见列数 + 1)
#   (可见列数-1 个列间竖线 + 左右两条边框边 —— 40x10 实测: 4 + 33 + 3 = 40 ✓)
#   SESSION = 终端宽 - 其余可见列宽 - (可见列数 + 1), 于是列宽之和**正好等于**
#   终端宽: 表格既不溢出也不留空洞, 名称列自然吸收全部余量。

function New-TmuxTuiColumnPlan {
    <#
    .SYNOPSIS
        按终端窗口宽度生成会话表格的列布局计划(纯函数)。

    .DESCRIPTION
        返回 PSCustomObject 数组, 顺序即列序:
            {No}      固定宽度 4
            {SESSION} 会话名, **吃满剩余宽度**(Min=Max=余量; 余量 <12 时取 12)
            {STATUS}  10 宽, 居中对齐; 终端 <96 列时 Visible=$false
            {WINDOWS} 9 宽, 右对齐; 终端 <72 列隐藏
        每项字段: Name / MinWidth / MaxWidth / RightAlign / CenterAlign /
        Alignment / Visible。

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

    # 固定宽度列
    $noWidth = 4
    $statusWidth = 10
    $windowsWidth = 9

    # 可见列集合(与 New-TmuxTuiSessionTable 的挂列顺序一致)
    $visibleCount = 2                                  # No + SESSION 恒可见
    $fixedWidth = $noWidth
    if ($showStatus) { $visibleCount++; $fixedWidth += $statusWidth }
    if ($showWindows) { $visibleCount++; $fixedWidth += $windowsWidth }

    # SESSION 吃满余量: 总宽 = Σ列宽 + (可见列数 + 1)
    $sessionWidth = $WindowWidth - $fixedWidth - ($visibleCount + 1)
    if ($sessionWidth -lt 12) { $sessionWidth = 12 }
    # ★ 上限 100: TG 2.4.10 的 TableView.MaxCellWidth 默认 100, 任何列的单元格
    #   宽度都被硬顶在 100 列(真机 130/160 列取证: 计划 132, 实际渲染 100)。
    #   且**不能调大 MaxCellWidth**: 实测 102/132 会让 TG 的 TableView 布局死循环。
    #   故计划侧就按 100 封顶 —— 计划与渲染一致, 终端宽于 128 列时表格保持 128 宽,
    #   右侧留白(不硬撑, 免得末列变成几十列的空洞)。
    if ($sessionWidth -gt 100) { $sessionWidth = 100 }

    return @(
        [PSCustomObject]@{ Name = 'No'; MinWidth = $noWidth; MaxWidth = $noWidth; RightAlign = $false; CenterAlign = $false; Alignment = 'Start'; Visible = $true }
        [PSCustomObject]@{ Name = 'SESSION'; MinWidth = $sessionWidth; MaxWidth = $sessionWidth; RightAlign = $false; CenterAlign = $false; Alignment = 'Start'; Visible = $true }
        [PSCustomObject]@{ Name = 'STATUS'; MinWidth = $statusWidth; MaxWidth = $statusWidth; RightAlign = $false; CenterAlign = $true; Alignment = 'Center'; Visible = $showStatus }
        [PSCustomObject]@{ Name = 'WINDOWS'; MinWidth = $windowsWidth; MaxWidth = $windowsWidth; RightAlign = $true; CenterAlign = $false; Alignment = 'End'; Visible = $showWindows }
    )
}
