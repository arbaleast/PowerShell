# New-TmuxTuiSessionRowList.ps1 - tmux 会话仪表盘的**自定义会话行列表**
#
# 背景 (2026-10-31 sss 仪表盘重构 · tmux 侧并入):
#   旧实现用 TG 的 TableView 渲染会话表。TableView 每次**选中变化**都把
#   **整张表**标记为脏(实测 NeedsDrawRect = {0,0,80,22} = 1760 单元格),
#   每次按键都重绘整表 —— 这与 SSH 主机列表是**同一个**延迟根因
#   (实测重绘均值 17.2ms; 真机上还要把整屏单元格写进终端)。
#   因此 tmux 侧改用与主机列表同构的"每行一组 Label"复合视图:
#     移动选中**只重刷旧/新两行**, 其余行不标脏。
#
# ★ 为什么拆成 5 个 Label 而不是 1 个:
#   TG 2.4.10 的 Label 只有单一 Attribute, 无法在同一行里混排
#   "绿点 / 白会话名 / 灰状态 / 灰窗口数"。行的**背景条**由整行宽的
#   Label(空格文本)提供 —— 实测 Label 会按自身 Scheme 刷背景色,
#   所以"选中行整行紫底"是真实背景而不是字符模拟。
#
# ★ 2026-11-06 #9b871512 "Forest Matrix"(翡翠绿/竹青)重构:
#   选中态**不再铺任何底色** —— 阶段一的"整行纯蓝(0,0,255)"在 Windows
#   Terminal 上依然刺眼(大面积高饱和蓝铺满一行, 对比度过载)。新做法:
#     - 背景**恒为 Black**(选中与未选中都一样);
#     - 选中态靠**序号徽标** ┃02┃ (U+2503, BrightGreen) 锚定位置,
#       未选中态同宽留白(" 01  ", DarkGray) => 两态会话名起点完全对齐;
#     - 选中行的会话名/窗口数提亮为 BrightWhite, 状态 Attached 恒亮绿;
#     - 状态列改**简写** "● Att" / "○ Det"(各 5 列), 消灭"会话名与状态
#       之间的大跨度黑洞;
#     - 窗口数列改 "3w" 形态, 右对齐 4 列。
#   ★ 严禁用字母 o 充当图标 —— 一律用正规 Unicode 符号(● ○ ┃ · ─ │)。
#
# ★ 为什么移动选中不重建 View:
#   槽位是**固定**的(数量 = 列表可视高度), 滚动时复用槽位重填内容。
#   重建 View 会让 TG 重排整棵树, 那才是性能倒退。
#
# 契约:
#   - New-TmuxTuiSessionRowList 只组装(无头可测, 不进事件循环、不读数据源);
#   - Set-TmuxTuiSessionSlot / Update-TmuxTuiSessionSelection /
#     Set-TmuxTuiSessionScroll 都是"数据 -> 视图"的纯刷新函数, 由编排层
#     在键盘回调里调用;
#   - 选中变化路径(Update-TmuxTuiSessionSelection)**只改两行**, 不重建任何 View。

function Get-TmuxTuiStateShort {
    <#
    .SYNOPSIS
        把会话状态压成列表用的**简写**(纯函数)。

    .DESCRIPTION
        #9b871512: 左栏变窄后, "Attached"/"Detached" 八个字符会把会话名与
        状态之间拉出"大跨度黑洞"。改成 5 字符的简写:
            Attached  -> "● Att"
            Detached  -> "○ Det"
        未知/空状态 -> "○ Det"(按空闲处理, 不伪造状态)。

        符号 + 文字**双重表达**(16 色终端里不靠颜色单独承载语义):
        实心 ● = 有客户端连着, 空心 ○ = 空闲。

    .PARAMETER Status
        原始状态文本('Attached'/'Detached'/'attached'/'detached'/空)。

    .OUTPUTS
        [string] 简写状态文本。

    .EXAMPLE
        Get-TmuxTuiStateShort -Status 'Attached'   # => '● Attached' 的简写 '● Att'
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Status
    )

    $filled = [string][char]0x25CF   # ●
    $hollow = [string][char]0x25CB   # ○
    if ([string]::IsNullOrEmpty($Status)) { return "$hollow Det" }
    if ($Status -match '(?i)^attached') { return "$filled Att" }
    return "$hollow Det"
}

function Get-TmuxTuiSessionRowGeometry {
    <#
    .SYNOPSIS
        按会话列表可视宽度算出各列的 X 偏移与宽度(列几何的唯一计算点)。

    .DESCRIPTION
        列固定为: 序号徽标(6) | 会话名(吃满) | 状态简写(6, 右对齐) | 窗口数(4, 右对齐)。

        ★ 2026-11-06 #9b871512 "Forest Matrix" 重构:
          - 最左列不再是 2 列的状态点, 而是 **6 列的序号徽标**:
              选中行 ┃02┃  (BrightGreen, U+2503 包裹两位序号)
              未选中行 " 01  " (DarkGray, 左右各留一个空格对齐)
            徽标**只做位置锚点**, 不铺背景 —— 选中态靠前景色 + 徽标形状
            区分, 彻底取消"整行涂蓝"。
          - 状态列改**简写**: Attached -> "● Att", Detached -> "○ Det"
            (各 5 列 + 1 空隙 = 6 列), 不再用 8 字符的 "Attached"/"Detached",
            消灭"会话名与状态之间的大跨度黑洞"。
          - 窗口数列改 "3w" 形态(数字 + w), 右对齐 4 列。
          - 状态点**不再另占一列**: Attached 恒 BrightGreen(选中与否一致),
            Detached 未选中 DarkGray / 选中 White。

        响应式取舍(名称优先): 列表变窄时**先舍次要列**, 保会话名。
          < 26 列: 只剩 序号徽标 + 会话名(状态/窗口数都藏掉)
          < 34 列: 保留状态, 藏掉窗口数
          >= 34 列: 三列全留

    .PARAMETER Width
        列表可视宽度(列)。

    .OUTPUTS
        [PSCustomObject] DotX/DotWidth/NameX/NameWidth/StatusX/StatusWidth/
                        WindowsX/WindowsWidth

    .EXAMPLE
        $g = Get-TmuxTuiSessionRowGeometry -Width 60
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [int]$Width
    )

    # 序号徽标: "┃02┃" = 1 + 2 + 1 = 4 列可见字符; 徽标占 6 列
    # (左边 1 列空隙 + 4 列徽标 + 右边 1 列空隙), 未选中态用空格占位,
    # 保证"选中/未选中"两态的会话名起点**完全对齐**。
    $dotX = 1
    $dotWidth = 6
    $statusWidth = 6
    $windowsWidth = 4
    $nameX = $dotX + $dotWidth

    # 响应式取舍(与旧列计划同一思路): 列表变窄时**先舍次要列**, 保会话名。
    if ($Width -lt 26) {
        $statusWidth = 0
        $windowsWidth = 0
    }
    elseif ($Width -lt 34) {
        $windowsWidth = 0
    }

    # 右侧固定宽度列, 会话名吃满中间
    $windowsX = if ($windowsWidth -gt 0) {
        [Math]::Max($nameX + 6, $Width - $windowsWidth - 1)
    }
    else {
        $Width
    }
    $statusX = if ($statusWidth -gt 0) {
        [Math]::Max($nameX + 4, $windowsX - $statusWidth - 1)
    }
    else {
        $windowsX
    }
    $nameWidth = $statusX - $nameX - 1
    if ($nameWidth -lt 4) {
        # 极窄: 状态列让位保会话名(名称优先)
        $statusWidth = 0
        $statusX = $windowsX
        $nameWidth = $windowsX - $nameX - 1
    }
    if ($nameWidth -lt 4) { $nameWidth = 4 }

    return [PSCustomObject]@{
        DotX        = $dotX
        DotWidth    = $dotWidth
        NameX       = $nameX
        NameWidth   = $nameWidth
        StatusX     = $statusX
        StatusWidth = $statusWidth
        WindowsX    = $windowsX
        WindowsWidth = $windowsWidth
    }
}

function New-TmuxTuiSessionRowList {
    <#
    .SYNOPSIS
        组装 tmux 会话列表(容器 View + 每行 5 个 Label 的槽位)。

    .DESCRIPTION
        行槽位数 = 列表可视高度; 槽位是**固定**的, 滚动时复用槽位重填内容。
        返回的对象既给编排层挂键盘回调, 也给刷新函数当句柄。

    .PARAMETER Rows
        会话行视图模型(ConvertTo-TmuxTuiViewModel 的 .SessionRows)。

    .PARAMETER Width
        列表可视宽度(列)。

    .PARAMETER Height
        列表可视高度(行, = 槽位数)。

    .PARAMETER SelectedIndex
        初始选中行在 Rows 中的下标(-1 = 不选中)。

    .PARAMETER Theme
        Get-TuiDashboardTheme 产物(与 SSH 主机仪表盘共用同一套语义 Scheme)。

    .PARAMETER Tgui
        Get-TguiContext 产物。

    .OUTPUTS
        [PSCustomObject] View/Slots/Rows/Width/Height/Top/SelectedIndex/Theme/Tgui/Geometry

    .EXAMPLE
        $list = New-TmuxTuiSessionRowList -Rows $rows -Width 60 -Height 24 -SelectedIndex 0 -Theme $theme -Tgui $tg
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [object[]]$Rows = @(),

        [Parameter(Mandatory = $true)]
        [ValidateRange(20, 500)]
        [int]$Width,

        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 200)]
        [int]$Height,

        [Parameter(Mandatory = $false)]
        [int]$SelectedIndex = -1,

        [Parameter(Mandatory = $true)]
        [object]$Theme,

        [Parameter(Mandatory = $true)]
        [object]$Tgui
    )

    if ($PSCmdlet.ShouldProcess('tmux 会话列表视图', 'Construct')) { } else { return $null }

    $static = [System.Reflection.BindingFlags]'Public,Static'
    $posAbsolute = $Tgui.Types.Pos.GetMethods($static) |
        Where-Object { $_.Name -eq 'Absolute' -and $_.GetParameters().Count -eq 1 } |
        Select-Object -First 1
    $dimAbsolute = $Tgui.Types.Dim.GetMethods($static) |
        Where-Object { $_.Name -eq 'Absolute' -and $_.GetParameters().Count -eq 1 } |
        Select-Object -First 1
    $labelType = $Tgui.Types.Label
    $viewType = $Tgui.Types.View

    $container = [System.Activator]::CreateInstance($viewType)
    $container.X = $posAbsolute.Invoke($null, @(0))
    $container.Y = $posAbsolute.Invoke($null, @(0))
    $container.Width = $dimAbsolute.Invoke($null, @($Width))
    $container.Height = $dimAbsolute.Invoke($null, @($Height))
    # 容器必须可聚焦才能收到方向键(方向键语义由编排层在 KeyDown 里实现,
    # 不用 TG 的 ListView/TableView —— 它们改选中就会整块重绘)
    $container.CanFocus = $true
    [void]$container.SetScheme($Theme.Text)

    $geo = Get-TmuxTuiSessionRowGeometry -Width $Width
    $alignEnum = $labelType.GetProperty('TextAlignment').PropertyType

    $slots = [System.Collections.Generic.List[object]]::new()
    for ($i = 0; $i -lt $Height; $i++) {
        $rowView = [System.Activator]::CreateInstance($viewType)
        $rowView.X = $posAbsolute.Invoke($null, @(0))
        $rowView.Y = $posAbsolute.Invoke($null, @($i))
        $rowView.Width = $dimAbsolute.Invoke($null, @($Width))
        $rowView.Height = $dimAbsolute.Invoke($null, @(1))
        [void]$rowView.SetScheme($Theme.Text)

        # 背景条: 整行宽的空格 Label —— 选中时换成暗蓝底方案, 得到"整行高亮"
        # (阶段一: 取代旧的高饱和洋红底, 低对比不刺眼且行内文字都提得亮)
        $bg = [System.Activator]::CreateInstance($labelType)
        $bg.Text = (' ' * $Width)
        $bg.Width = $dimAbsolute.Invoke($null, @($Width))
        $bg.Height = $dimAbsolute.Invoke($null, @(1))
        $bg.X = $posAbsolute.Invoke($null, @(0))
        $bg.Y = $posAbsolute.Invoke($null, @(0))
        [void]$bg.SetScheme($Theme.Text)

        function New-SessionRowLabel {
            # 纯视图工厂(只 new 一个 Label), 不改变系统状态
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
            param([int]$X, [int]$W, [string]$Text, [object]$Scheme, [bool]$RightAlign = $false)
            $lbl = [System.Activator]::CreateInstance($labelType)
            $lbl.Text = $Text
            $lbl.X = $posAbsolute.Invoke($null, @($X))
            $lbl.Y = $posAbsolute.Invoke($null, @(0))
            $lbl.Width = $dimAbsolute.Invoke($null, @([Math]::Max(1, $W)))
            $lbl.Height = $dimAbsolute.Invoke($null, @(1))
            [void]$lbl.SetScheme($Scheme)
            if ($RightAlign) {
                try { $lbl.TextAlignment = [Enum]::Parse($alignEnum, 'End') }
                catch { Write-Verbose "[New-TmuxTuiSessionRowList] 右对齐设置失败: $($_.Exception.Message)" }
            }
            return $lbl
        }

        $dot = New-SessionRowLabel -X $geo.DotX -W $geo.DotWidth -Text '' -Scheme $Theme.ForestBadgeOff
        $name = New-SessionRowLabel -X $geo.NameX -W $geo.NameWidth -Text '' -Scheme $Theme.ForestName
        $status = New-SessionRowLabel -X $geo.StatusX -W ([Math]::Max(1, $geo.StatusWidth)) -Text '' -Scheme $Theme.ForestDetached -RightAlign $true
        $windows = New-SessionRowLabel -X $geo.WindowsX -W $geo.WindowsWidth -Text '' -Scheme $Theme.ForestWinCount -RightAlign $true

        foreach ($lbl in @($bg, $dot, $name, $status, $windows)) { [void]$rowView.Add($lbl) }
        [void]$container.Add($rowView)

        $slots.Add([PSCustomObject]@{
                Index    = $i
                View     = $rowView
                Bg       = $bg
                Dot      = $dot
                Name     = $name
                Status   = $status
                Windows  = $windows
                RowIndex = -1
                Selected = $false
            })
    }

    $listView = [PSCustomObject]@{
        View          = $container
        Slots         = $slots.ToArray()
        Rows          = @($Rows)
        Width         = $Width
        Height        = $Height
        Top           = 0
        SelectedIndex = $SelectedIndex
        Theme         = $Theme
        Tgui          = $Tgui
        Geometry      = $geo
    }

    # 首帧填充: 选中行先滚到可视区(选中优先保证可见)
    if ($SelectedIndex -ge 0 -and $SelectedIndex -lt $listView.Rows.Count) {
        $top = [Math]::Max(0, $SelectedIndex - [int][Math]::Floor($Height / 2))
        $listView.Top = [Math]::Min($top, [Math]::Max(0, $listView.Rows.Count - $Height))
    }
    Set-TmuxTuiSessionScroll -ListView $listView

    return $listView
}

function Set-TmuxTuiSessionSlot {
    <#
    .SYNOPSIS
        把一个槽位填成指定会话行(文本 + 配色); 空行则清空。

    .PARAMETER ListView
        New-TmuxTuiSessionRowList 产物(会被就地更新 RowIndex/Selected)。

    .PARAMETER SlotIndex
        槽位下标(0..Height-1)。

    .PARAMETER RowIndex
        该槽位对应的 Rows 下标; -1 表示空格位。

    .PARAMETER Selected
        该行当前是否选中。
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$ListView,

        [Parameter(Mandatory = $true)]
        [int]$SlotIndex,

        [Parameter(Mandatory = $true)]
        [int]$RowIndex,

        [Parameter(Mandatory = $false)]
        [bool]$Selected = $false
    )

    if ($SlotIndex -lt 0 -or $SlotIndex -ge $ListView.Slots.Count) { return }
    $slot = $ListView.Slots[$SlotIndex]
    $theme = $ListView.Theme
    $geo = $ListView.Geometry
    $slot.RowIndex = $RowIndex
    $slot.Selected = $Selected

    if ($RowIndex -lt 0 -or $RowIndex -ge $ListView.Rows.Count) {
        # 空格位: 背景用黑底把缩放/过滤后的残影擦掉
        $slot.Bg.Text = (' ' * $ListView.Width)
        [void]$slot.Bg.SetScheme($theme.Text)
        $slot.Dot.Text = ''
        [void]$slot.Dot.SetScheme($theme.ForestBadgeOff)
        $slot.Name.Text = ''
        [void]$slot.Name.SetScheme($theme.ForestName)
        $slot.Status.Text = ''
        [void]$slot.Status.SetScheme($theme.ForestDetached)
        $slot.Windows.Text = ''
        [void]$slot.Windows.SetScheme($theme.ForestWinCount)
        return
    }

    $row = $ListView.Rows[$RowIndex]
    $isAttached = ([string]$row.Status -eq 'Attached')

    # ================================================================
    # 配色映射表(2026-11-06 #9b871512 "Forest Matrix")
    # ================================================================
    # 原则: **背景恒为 Black**(不铺任何饱和底色), 靠前景色 + 徽标形状分层。
    #
    # 未选中行(Normal):
    #   背景     Black
    #   序号徽标 " 01  "  DarkGray   (与选中态同宽, 保证会话名起点对齐)
    #   会话名   Gray
    #   状态     "● Att" BrightGreen / "○ Det" DarkGray
    #   窗口数   "3w"   DarkGray
    #
    # 选中行(Selected):
    #   背景     Black                    <- **不铺底色**(阶段一的纯蓝底已取消)
    #   序号徽标 "┃02┃"  BrightGreen      <- 强视觉锚点, 替代整行涂色
    #   会话名   BrightWhite              <- 提亮
    #   状态     "● Att" BrightGreen / "○ Det" White
    #   窗口数   "3w"   BrightWhite       <- 提亮
    #
    # 不变量(测试断言):
    #   - 选中行的**任何**文本片段都不得是 DarkGray 前景(暗字在黑底上不可读);
    #   - Attached 状态**无论选中与否**都是 BrightGreen(状态语义恒定);
    #   - 徽标只用 U+2503(┃)与空格, **禁止**用字母 o 当图标。
    $badge = ''
    try { $badge = ([int]$row.No).ToString('00') } catch { $badge = '00' }
    if ($badge.Length -gt 2) { $badge = $badge.Substring($badge.Length - 2) }

    $windowsCount = 0
    try { $windowsCount = [int]$row.Windows } catch { $windowsCount = 0 }

    if ($Selected) {
        [void]$slot.Bg.SetScheme($theme.Text)
        # 序号徽标: ┃02┃ (U+2503 包裹), BrightGreen
        $slot.Dot.Text = ([string][char]0x2503) + $badge + ([string][char]0x2503)
        [void]$slot.Dot.SetScheme($theme.ForestBadge)

        $slot.Name.Text = Get-SshHostListClip -Text ([string]$row.Session) -Width $geo.NameWidth
        [void]$slot.Name.SetScheme($theme.ForestNameOn)

        if ($geo.StatusWidth -gt 0) {
            $slot.Status.Text = Get-SshHostListClip -Text (Get-TmuxTuiStateShort -Status ([string]$row.Status)) -Width $geo.StatusWidth
            [void]$slot.Status.SetScheme($(if ($isAttached) { $theme.ForestAttached } else { $theme.ForestDetachedOn }))
        }
        else {
            $slot.Status.Text = ''
        }

        $slot.Windows.Text = Get-SshHostListClip -Text ("$windowsCount" + 'w') -Width $geo.WindowsWidth
        [void]$slot.Windows.SetScheme($theme.ForestWinCountOn)
        return
    }

    # ---- 未选中行 ----
    [void]$slot.Bg.SetScheme($theme.Text)

    # 序号徽标: 纯空格占位(与选中态同宽 -> 会话名起点对齐)
    $slot.Dot.Text = "  $badge  "
    [void]$slot.Dot.SetScheme($theme.ForestBadgeOff)

    $slot.Name.Text = Get-SshHostListClip -Text ([string]$row.Session) -Width $geo.NameWidth
    [void]$slot.Name.SetScheme($theme.ForestName)

    if ($geo.StatusWidth -gt 0) {
        $slot.Status.Text = Get-SshHostListClip -Text (Get-TmuxTuiStateShort -Status ([string]$row.Status)) -Width $geo.StatusWidth
        # ★ Attached 恒亮绿(选中与否一致) —— 状态语义不随选中态漂移。
        [void]$slot.Status.SetScheme($(if ($isAttached) { $theme.ForestAttached } else { $theme.ForestDetached }))
    }
    else {
        $slot.Status.Text = ''
    }

    $slot.Windows.Text = Get-SshHostListClip -Text ("$windowsCount" + 'w') -Width $geo.WindowsWidth
    [void]$slot.Windows.SetScheme($theme.ForestWinCount)
}

function Update-TmuxTuiSessionSelection {
    <#
    .SYNOPSIS
        移动选中行 —— **只**重刷旧/新两行(键盘热路径, 不重建 View)。

    .DESCRIPTION
        选中变化只影响两行的配色, 因此这里只调用这两行槽位的 Set-TmuxTuiSessionSlot
        (改 Label 的 Text/Scheme), 让 TG 的脏区机制只重画这两行。
        越界/相同下标直接返回(幂等)。

    .PARAMETER ListView
        New-TmuxTuiSessionRowList 产物。

    .PARAMETER OldIndex
        原选中行下标(-1 = 无)。

    .PARAMETER NewIndex
        新选中行下标(-1 = 无)。

    .OUTPUTS
        [bool] 是否真的发生了重绘(供编排层记录性能日志)。
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$ListView,

        [Parameter(Mandatory = $false)]
        [int]$OldIndex = -1,

        [Parameter(Mandatory = $false)]
        [int]$NewIndex = -1
    )

    if ($OldIndex -eq $NewIndex) { return $false }
    $ListView.SelectedIndex = $NewIndex
    $changed = $false
    foreach ($idx in @($OldIndex, $NewIndex)) {
        if ($idx -lt 0) { continue }
        $slotIdx = $idx - $ListView.Top
        if ($slotIdx -lt 0 -or $slotIdx -ge $ListView.Slots.Count) { continue }
        $selected = ($idx -eq $NewIndex)
        Set-TmuxTuiSessionSlot -ListView $ListView -SlotIndex $slotIdx -RowIndex $idx -Selected $selected
        $changed = $true
    }
    return $changed
}

function Set-TmuxTuiSessionScroll {
    <#
    .SYNOPSIS
        把可见窗口滚到指定 Top 并重填槽位(滚动时用)。

    .DESCRIPTION
        逐槽比对: 内容与选中态都**没变**的槽位直接跳过 —— SetScheme/Text
        赋值都会把 Label 标脏, 跳过"内容没变的重画"(同一 Top 重新滚动 /
        窗口重建后内容相同)。
        ⚠️ 边界: 真正滚动一行时, 每个可见槽位显示的是**不同的会话**,
        内容确实变了, 必须整屏重画 —— 跳过逻辑**不会**把滚动脏区缩到两行。

    .PARAMETER ListView
        New-TmuxTuiSessionRowList 产物。

    .PARAMETER Top
        可选: 新的首个可见行下标; 省略则沿用当前 Top(只重填内容)。
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$ListView,

        [Parameter(Mandatory = $false)]
        [int]$Top = -1
    )

    if ($Top -ge 0) { $ListView.Top = $Top }
    $maxTop = [Math]::Max(0, @($ListView.Rows).Count - $ListView.Height)
    if ($ListView.Top -gt $maxTop) { $ListView.Top = $maxTop }
    if ($ListView.Top -lt 0) { $ListView.Top = 0 }

    for ($i = 0; $i -lt $ListView.Slots.Count; $i++) {
        $rowIndex = $ListView.Top + $i
        if ($rowIndex -ge @($ListView.Rows).Count) { $rowIndex = -1 }
        $selected = ($rowIndex -ge 0 -and $rowIndex -eq $ListView.SelectedIndex)
        $slot = $ListView.Slots[$i]
        if ($slot.RowIndex -eq $rowIndex -and $slot.Selected -eq $selected) { continue }
        Set-TmuxTuiSessionSlot -ListView $ListView -SlotIndex $i -RowIndex $rowIndex -Selected $selected
    }
}

function Move-TmuxTuiSessionSelection {
    <#
    .SYNOPSIS
        上下移动选中(带边界夹取, 幂等)。

    .PARAMETER ListView
        New-TmuxTuiSessionRowList 产物。

    .PARAMETER Delta
        +1 下移 / -1 上移。

    .OUTPUTS
        [bool] 是否真的移动了。
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$ListView,

        [Parameter(Mandatory = $true)]
        [int]$Delta
    )

    $count = @($ListView.Rows).Count
    if ($count -eq 0) { return $false }
    $oldIndex = [int]$ListView.SelectedIndex
    $newIndex = $oldIndex + $Delta
    if ($newIndex -lt 0) { $newIndex = 0 }
    if ($newIndex -ge $count) { $newIndex = $count - 1 }
    if ($newIndex -eq $oldIndex) { return $false }
    [void](Update-TmuxTuiSessionSelection -ListView $ListView -OldIndex $oldIndex -NewIndex $newIndex)
    return $true
}

function Sync-TmuxTuiSessionScroll {
    <#
    .SYNOPSIS
        保证选中行在可视窗口内(需要时滚动并重填槽位)。

    .DESCRIPTION
        ★ 为什么必须做(实测缺陷, 2026-11 性能与稳定性审计):
          Update-TmuxTuiSessionSelection 只刷新"旧行/新行"两个槽位, 且
          **跳过越界槽位**(slotIdx < 0 或 >= Slots.Count)。当选中行移出
          可视区(行数 > 可视高度, 这在真实 tmux 环境很常见)时:
            - 旧行(还在可视区)被取消高亮;
            - 新行(已在可视区外)**没有任何槽位**承载它 → 不刷新、不显示;
            - 于是**屏幕上没有任何一行处于选中态**, 而右侧详情卡已经切到
              新会话 —— 界面自相矛盾, 用户既看不到自己选中了谁, 也无法
              判断 Enter 会连到哪台机器。
          实测(100 行 / 可视 10 行, 连按 15 次下移): Top 恒为 0、
          SelectedIndex=15、处于选中态的槽位数 = 0。

        做法与 SSH 主机仪表盘的 Sync-SshHostDashboardScroll 同构:
          选中行落在可视区外时, 把 Top 移到能看见它的位置, 再由
          Set-TmuxTuiSessionScroll 重填槽位(内容没变的槽位会被跳过)。

    .PARAMETER ListView
        New-TmuxTuiSessionRowList 产物。

    .OUTPUTS
        [bool] 是否真的滚动了(未滚动返回 $false)。
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$ListView
    )

    $index = [int]$ListView.SelectedIndex
    if ($index -lt 0) { return $false }

    $top = [int]$ListView.Top
    $height = [int]$ListView.Height
    $target = $top
    if ($index -lt $top) { $target = $index }
    elseif ($index -ge ($top + $height)) { $target = $index - $height + 1 }

    $maxTop = [Math]::Max(0, @($ListView.Rows).Count - $height)
    if ($target -lt 0) { $target = 0 }
    if ($target -gt $maxTop) { $target = $maxTop }

    if ($target -ne $top) {
        Set-TmuxTuiSessionScroll -ListView $ListView -Top $target
        return $true
    }
    return $false
}
