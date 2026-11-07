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
#   0        标题行   (ShellPrompt / TMUX MANAGER | 主机 | 连接状态)
#   1        统计行   (会话总数 / Attached / Detached, Attached 段高亮联动)
#   2        辅助行   (空态提示 或 错误码+原因+可执行操作; 有会话时留空)
#   3..H-2   主体区   (Height = H - 4)
#             ├─ 左侧会话列表(自定义行, 局部两行重绘)
#             ├─ 单条竖线 │ (DarkGray) + 2 列呼吸间距
#             └─ 右侧「会话工作区」三段式(无外框)
#   H-1      底部快捷键栏 (StatusBar, Pos.AnchorEnd())
#
# 分栏断点(2026-11-06 #9b871512 非对称三区驾驶舱, 取代阶段一的 42%/40%/50-54):
#   < 72 列    : Single —— 单栏, 只显示左侧列表, 右侧驾驶舱整体隐藏
#   72 - 99 列 : Dual   —— 列表 38% / 驾驶舱 62%
#   100-139 列 : Dual   —— 列表 34% / 驾驶舱 66%
#   >= 140 列  : Dual   —— 列表封顶 38~42 列, 剩余全给右侧驾驶舱
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
          .SplitMode                分栏模式: 'Single'(单栏) / 'Dual'(双栏)
          .ListWidth                左侧会话列表宽度(列)
          .DividerX                 分隔竖线所在列(-1 = 不画)
          .DetailX                  右侧工作区起始列(-1 = 不画)
          .DetailWidth              右侧工作区宽度(列; 单栏时 0)
          .ListRatio                左侧列表占屏比例(单栏时 1.0)

        不变量(测试直接断言):
          - TableRow(=3) > HintRow(=2) > StatsRow(=1) > TitleRow(=0)   顶部不重叠
          - TableBottomRow(= Height - 2) < StatusBarRow(= Height - 1)  底部不重叠
          - TableHeight >= 1                                            极小窗口也不为负
          - 单栏模式: ListWidth = Width, DetailWidth = 0, DividerX = -1
          - 双栏模式: ListWidth + 1(竖线) + 2(呼吸间距) + DetailWidth = Width
          - ListWidth >= 1, DetailWidth >= 1(双栏时), 两者都不为负

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
    # 会话区占 3..H-2 共 (H-4) 行 —— **表格的排他底边必须正好等于快捷键栏顶行
    # (H-1)**, 否则主体区与底栏之间会空出 1 行(零重叠零空档是本仓库的硬约束)。
    # ★ 2026-10-31 修正: 原式子 `$Height - $tableRow - $statusBarHeight - 1`
    #   算出来是 H-5, 与本文件头的契约("= Height - 4")**不一致**, 少了一行。
    #   旧实现用 TableView + Dim.Fill(margin) 撑高度, 绕过了这个字段, 所以偏差
    #   一直没暴露; 换成自定义行列表(按 TableHeight 绝对定位)后立刻变成"主体区
    #   与底栏之间空一行"。此处按契约改正。
    $titleRow = 0
    $statsRow = 1
    $hintRow = 2
    $tableRow = 3
    $statusBarHeight = 1
    $statusBarRow = $Height - 1
    $tableHeight = $Height - $tableRow - $statusBarHeight   # = Height - 4 => 行 3..H-2
    if ($tableHeight -lt 1) { $tableHeight = 1 }

    # ================================================================
    # 分栏几何(2026-11-06 #9b871512 · 非对称三区驾驶舱)
    # ================================================================
    # 阶段一的实现: 72-99 列表 42% / 100-139 列表 40% / >=140 列表封顶 50-54 列。
    # #9b871512 把左侧**再压缩**: 状态简写成 "○ Det"/"● Att" + "3w" 之后,
    # 一行只需要 ≈ 40 列(序号徽标 6 + 会话名 + 状态 6 + 窗口数 4), 再宽的左栏
    # 只会拉出"会话名与状态之间的大跨度黑洞"。因此:
    #   < 72 列  : 单栏(只显示左侧列表, 右侧驾驶舱整体隐藏)
    #   72-99    : 双栏, 列表 38% / 驾驶舱 62%
    #   100-139  : 双栏, 列表 34% / 驾驶舱 66%
    #   >= 140   : 双栏, 列表**封顶 38~42 列**, 右侧吃掉全部余量
    #
    # 竖线与呼吸间距(保持"全窗只有一条竖线"):
    #   左列表 | 1 列竖线 │ | 2 列呼吸间距 | 右驾驶舱
    $splitMode = 'Single'
    $listRatio = 1.0
    $listWidth = $Width
    $dividerX = -1
    $detailX = -1
    $detailWidth = 0

    if ($Width -ge 72) {
        $splitMode = 'Dual'
        if ($Width -ge 140) {
            # 大屏: 34% 但封顶 42 列(下限 38) —— 右侧驾驶舱吃掉全部余量
            $listWidth = [int][Math]::Floor($Width * 0.34)
            if ($listWidth -gt 42) { $listWidth = 42 }
            if ($listWidth -lt 38) { $listWidth = 38 }
            $listRatio = [Math]::Round($listWidth / $Width, 4)
        }
        elseif ($Width -ge 100) {
            $listRatio = 0.34
            $listWidth = [int][Math]::Floor($Width * 0.34)
        }
        else {
            $listRatio = 0.38
            $listWidth = [int][Math]::Floor($Width * 0.38)
        }

        # 右侧驾驶舱至少 30 列(SUMMARY 双栏 + 预览框才排得开), 不够就退回单栏
        $detailWidth = $Width - $listWidth - 3   # 1 列竖线 + 2 列呼吸间距
        if ($detailWidth -lt 30) {
            # 右侧放不下 -> 退回单栏(宁可单栏也不要半截驾驶舱)
            $splitMode = 'Single'
            $listRatio = 1.0
            $listWidth = $Width
            $dividerX = -1
            $detailX = -1
            $detailWidth = 0
        }
        else {
            $dividerX = $listWidth        # 竖线紧贴列表右缘(列表占 0..listWidth-1)
            $detailX = $listWidth + 3    # 竖线(1) + 呼吸间距(2)
        }
    }

    # 列表宽度硬下限: 状态点 + 会话名至少要放得下(几何函数另有细粒度取舍)
    if ($listWidth -lt 20) { $listWidth = 20 }
    if ($splitMode -eq 'Single') {
        $listWidth = $Width
    }

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
        SplitMode        = $splitMode
        ListWidth        = $listWidth
        ListRatio        = $listRatio
        DividerX         = $dividerX
        DetailX          = $detailX
        DetailWidth      = $detailWidth
    }
}
