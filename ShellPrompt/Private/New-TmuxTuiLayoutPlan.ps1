# New-TmuxTuiLayoutPlan.ps1 - TGUI 仪表盘的**几何布局计划**(纯函数)
#
# 背景 (2026-10-30 TGUI 迁移 · 阶段 B):
#   Goal 三-5 要求"窗口缩放后自动重新布局, 不允许表格/状态栏/快捷键栏互相覆盖"。
#   Terminal.Gui 2.4.10 的布局语义(反射实测, 见 .agent_cache/tgui-probe/REPORT.md):
#     - Window.BorderStyle = $null 时, Window 的**内容区 == 整个 Frame**
#       (BorderStyle=Single 时内容区会被边框吃掉 2 行 2 列, 绝对坐标就对不齐屏幕);
#     - Pos.Absolute(n) = 相对内容区左上角偏移 n;
#     - Pos.AnchorEnd()  = 贴内容区下边缘;
#     - Dim.Fill()       = 撑满内容区 —— 因此"表格 Fill + 状态栏 AnchorEnd"
#       必然重叠 1 行, 本仓库改用**绝对高度**杜绝重叠。
#   所以几何必须由"屏幕尺寸"一次算出, 窗口重建时复用 —— 这就是本函数。
#
# 行分配(内容区行号, 0 基):
#   0        标题行   (ShellPrompt TMUX Manager | 主机 | 连接状态)
#   1        统计行   (会话总数 / Attached / Detached)
#   2        辅助行   (空态提示 或 错误码+原因+可执行操作; 有会话时留空)
#   3..H-2   会话表格 (Height = H - 4)
#   H-1      底部快捷键栏 (StatusBar, Pos.AnchorEnd())
#
# 契约: 纯函数, 不触碰控制台/网络/TG —— 可对 100x30 / 120x35 / 160x45 三档直接断言。

function New-TmuxTuiLayoutPlan {
    <#
    .SYNOPSIS
        按终端尺寸生成 TGUI 仪表盘的几何布局计划(纯函数)。

    .DESCRIPTION
        返回 PSCustomObject:
          .Width / .Height          计划对应的终端尺寸(已夹取到可用范围)
          .TitleRow                 标题行行号(0)
          .StatsRow                 统计行行号(1)
          .HintRow                  辅助行行号(2)
          .TableRow                 会话表格起始行(3)
          .TableHeight              会话表格高度(= Height - 4, 最少 1)
          .TableBottomRow           会话表格最后一行(= Height - 2)
          .StatusBarRow             快捷键栏行号(= Height - 1)
          .StatusBarHeight          快捷键栏高度(1)
          .Columns                  列计划(New-TmuxTuiColumnPlan 的产物)

        不变量(测试直接断言):
          - TableRow(=3) > HintRow(=2) > StatsRow(=1) > TitleRow(=0)   顶部不重叠
          - TableBottomRow(= Height - 2) < StatusBarRow(= Height - 1)  底部不重叠
          - TableHeight >= 1                                            极小窗口也不为负

    .PARAMETER Width
        终端可用列数(缺省 120)。

    .PARAMETER Height
        终端可用行数(缺省 35)。

    .OUTPUTS
        [PSCustomObject] 布局计划

    .EXAMPLE
        $plan = New-TmuxTuiLayoutPlan -Width 100 -Height 30
        $plan.TableBottomRow | Should -BeLessThan $plan.StatusBarRow
    #>
    # 纯函数, 不改系统状态 —— New- 动词按 PSSA 规则需显式豁免 ShouldProcess
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [ValidateRange(20, 1000)]
        [int]$Width = 120,

        [Parameter(Mandatory = $false)]
        [ValidateRange(6, 1000)]
        [int]$Height = 35
    )

    # 顶部固定 3 行(标题/统计/辅助) + 底部固定 1 行(快捷键栏) => 表格至少 1 行
    $titleRow = 0
    $statsRow = 1
    $hintRow = 2
    $tableRow = 3
    $statusBarHeight = 1
    $statusBarRow = $Height - 1
    $tableHeight = $Height - $tableRow - $statusBarHeight - 1   # = Height - 4
    if ($tableHeight -lt 1) { $tableHeight = 1 }

    return [PSCustomObject]@{
        Width            = $Width
        Height           = $Height
        TitleRow         = $titleRow
        StatsRow         = $statsRow
        HintRow          = $hintRow
        TableRow         = $tableRow
        TableHeight      = $tableHeight
        TableBottomRow   = $tableRow + $tableHeight - 1
        StatusBarRow     = $statusBarRow
        StatusBarHeight  = $statusBarHeight
        Columns          = @(New-TmuxTuiColumnPlan -WindowWidth $Width)
    }
}
