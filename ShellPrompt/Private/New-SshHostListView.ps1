# New-SshHostListView.ps1 - 仪表盘左侧主机列表的**自定义行列表**(装配 + 局部刷新)
#
# 背景 (2026-10-31 sss 仪表盘重构 · 性能主战场):
#   旧主机选择器用 Terminal.Gui 的 TableView 渲染列表, 上下键移动选中时
#   TG 会把**整个表格**标记为脏(实测: 选中变化后 TableView.NeedsDrawRect =
#   整张表 60x25), 于是每次按键都重绘整表。在 Windows Terminal 上这意味着
#   每次按键写出一整屏单元格, 正是用户报的 100~200ms 延迟。
#   实测数据(.agent_cache/dash-probe/p13-rowproto.ps1, 同一进程内对照):
#     TableView   每次按键重绘 15.04 ms(平均) / 脏区 = 整表
#     自定义行列表 每次按键重绘  4.41 ms(平均) / 脏区 = 两行
#   因此这里用"每行一组 Label"的复合视图自己管选中态: 移动选中时**只**改
#   旧/新两行的 Scheme(Label 的 SetScheme 会把该 Label 标脏), TG 原生
#   局部刷新只重画这两行, 不碰列表其余部分, 也不需要任何 Application.Refresh。
#
# ★ 为什么不用单个 Label 承载整行(而拆成 6 个 Label):
#   TG 2.4.10 的 Label 只有单一 Attribute, 无法在同一行里混排"绿点 / 白名称 /
#   暗灰分组 / 紫标签 / 灰时间"。行的**背景条**由整行宽的 Label(空格文本)提供
#   —— 实测 Label 会按自身 Scheme 刷背景色(p22-bg3.ps1 取证: 空格 Label 的
#   单元格 bg = #FF00FF), 所以"选中行整行紫底"是真实背景而不是字符模拟。
#
# ★ 为什么 SetScheme 就足够(不做额外的 SetNeedsDraw 强刷):
#   p13 实测: 只调用 Label.SetScheme 之后, 容器 NeedsDrawRect 不扩张到整表,
#   下一次 LayoutAndDraw 的平均耗时从整表重绘的 15ms 降到 4.4ms, 且屏幕内容
#   正确。也就是说"局部刷新"来自 TG 自身的脏区机制, 没有依赖手工强刷 ——
#   这正是 Goal 要求的"利用原生的局部刷新机制, 不硬来"。
#
# 契约:
#   - New-SshHostListView 只组装(无头可测, 不进事件循环、不读任何数据源);
#   - Set-SshHostListSlot / Update-SshHostListSelection / Set-SshHostListScroll /
#     Sync-SshHostListRow 都是"数据 -> 视图"的纯刷新函数, 由编排层在
#     键盘回调里调用;
#   - 选中变化路径(Update-SshHostListSelection)**只改两行**, 不重建任何 View。

function Get-SshHostListClip {
    <#
    .SYNOPSIS
        按**显示宽度**把文本裁到指定列数, 超长补省略号(U+2026)。

    .DESCRIPTION
        TG 的 Label 不负责截断: 文本超宽会被硬切在视图边界, 中文/全角字符
        还可能只露出半个(列对齐崩)。这里用 Get-TguiTextWidth 逐字符累计
        显示宽度, 保证截断后仍能整列对齐; 省略号是半角单列宽字符。

    .PARAMETER Text
        原始文本(可含中文/全角)。

    .PARAMETER Width
        可用列数(<=0 时返回空串)。

    .OUTPUTS
        [string] 截断后的文本。

    .EXAMPLE
        Get-SshHostListClip -Text '生产数据库-web-01' -Width 8   # => '生产数…'
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Text,

        [Parameter(Mandatory = $true)]
        [int]$Width
    )

    if ([string]::IsNullOrEmpty($Text) -or $Width -le 0) { return '' }

    $fullWidth = Get-TguiTextWidth -Text $Text
    if ($fullWidth -le $Width) { return $Text }

    # 留一列给省略号(U+2026, 单列宽)
    $budget = $Width - 1
    $sb = [System.Text.StringBuilder]::new()
    $used = 0
    foreach ($ch in $Text.ToCharArray()) {
        $w = Get-TguiTextWidth -Text ([string]$ch)
        if ($used + $w -gt $budget) { break }
        [void]$sb.Append($ch)
        $used += $w
    }
    return ($sb.ToString() + [string][char]0x2026)
}

function Get-SshHostListGeometry {
    <#
    .SYNOPSIS
        按列表可视宽度算出各列的 X 偏移与宽度(列几何的唯一计算点)。

    .DESCRIPTION
        列固定为: 状态点(2) | 名称 | 分组 | 标签 | 最后活跃(6, 右对齐)。
        名称/分组/标签吃满剩余宽度, 窄屏按档位压缩分组与标签列 ——
        宽度预算集中在这里算, 避免每个 Slot 各算一套导致列错位。

    .PARAMETER Width
        列表可视宽度(列)。

    .OUTPUTS
        [PSCustomObject] DotX/DotWidth/NameX/NameWidth/GroupX/GroupWidth/
                        TagsX/TagsWidth/TimeX/TimeWidth

    .EXAMPLE
        $g = Get-SshHostListGeometry -Width 56
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [int]$Width
    )

    $dotX = 1
    $dotWidth = 2
    $nameX = 4
    $timeWidth = 6
    $timeX = [Math]::Max($nameX + 6, $Width - $timeWidth - 1)

    # 档位: 宽屏给分组/标签留足; 窄屏先压标签, 再压分组
    if ($Width -ge 56) {
        $groupWidth = 10
        $tagsWidth = 14
    }
    elseif ($Width -ge 44) {
        $groupWidth = 8
        $tagsWidth = 10
    }
    else {
        $groupWidth = 0
        $tagsWidth = 8
    }
    $nameWidth = $timeX - $nameX - $groupWidth - $tagsWidth - 1
    if ($nameWidth -lt 6) {
        # 极窄: 标签让位保名称(名称优先, 次要信息降低权重)
        $tagsWidth = [Math]::Max(0, $tagsWidth - (6 - $nameWidth))
        $nameWidth = [Math]::Max(4, $timeX - $nameX - $groupWidth - $tagsWidth - 1)
    }

    return [PSCustomObject]@{
        DotX      = $dotX
        DotWidth  = $dotWidth
        NameX     = $nameX
        NameWidth = $nameWidth
        GroupX    = $nameX + $nameWidth
        GroupWidth = $groupWidth
        TagsX     = $nameX + $nameWidth + $groupWidth
        TagsWidth = $tagsWidth
        TimeX     = $timeX
        TimeWidth = $timeWidth
    }
}

function New-SshHostListView {
    <#
    .SYNOPSIS
        组装左侧主机列表(容器 View + 每行 6 个 Label 的槽位)。

    .DESCRIPTION
        行槽位数 = 列表可视高度; 槽位是**固定**的, 滚动时复用槽位重填内容
        (不重建 View —— 重建 View 会让 TG 重排整棵树, 那才是性能倒退)。
        返回的对象既给编排层挂键盘回调, 也给刷新函数当句柄。

    .PARAMETER Rows
        行视图模型(Get-SshHostDashboardRow 产物)。

    .PARAMETER Width
        列表可视宽度(列)。

    .PARAMETER Height
        列表可视高度(行, = 槽位数)。

    .PARAMETER SelectedIndex
        初始选中行在 Rows 中的下标(-1 = 不选中)。

    .PARAMETER Theme
        Get-SshHostDashboardTheme 产物。

    .PARAMETER Tgui
        Get-TguiContext 产物。

    .OUTPUTS
        [PSCustomObject] View/Slots/Rows/Width/Height/Top/SelectedIndex/Theme/Tgui

    .EXAMPLE
        $list = New-SshHostListView -Rows $rows -Width 56 -Height 24 -SelectedIndex 0 -Theme $theme -Tgui $tg
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

    if ($PSCmdlet.ShouldProcess('SSH 主机列表视图', 'Construct')) { } else { return $null }

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
    # 容器必须可聚焦才能收到方向键(方向键的语义由编排层在 KeyDown 里实现,
    # 不用 TG 的 ListView/TableView —— 它们改选中就会整块重绘)
    $container.CanFocus = $true
    [void]$container.SetScheme($Theme.Text)

    $slots = [System.Collections.Generic.List[object]]::new()
    for ($i = 0; $i -lt $Height; $i++) {
        $rowView = [System.Activator]::CreateInstance($viewType)
        $rowView.X = $posAbsolute.Invoke($null, @(0))
        $rowView.Y = $posAbsolute.Invoke($null, @($i))
        $rowView.Width = $dimAbsolute.Invoke($null, @($Width))
        $rowView.Height = $dimAbsolute.Invoke($null, @(1))
        [void]$rowView.SetScheme($Theme.Text)

        # 背景条: 整行宽的空格 Label —— 选中时换成紫底方案, 得到"整行高亮"
        $bg = [System.Activator]::CreateInstance($labelType)
        $bg.Text = (' ' * $Width)
        $bg.Width = $dimAbsolute.Invoke($null, @($Width))
        $bg.Height = $dimAbsolute.Invoke($null, @(1))
        $bg.X = $posAbsolute.Invoke($null, @(0))
        $bg.Y = $posAbsolute.Invoke($null, @(0))
        [void]$bg.SetScheme($Theme.Text)

        $geo = Get-SshHostListGeometry -Width $Width
        function New-RowLabel {
            # 纯视图工厂(只 new 一个 Label), 不改变系统状态
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
            param([int]$X, [int]$W, [string]$Text, [object]$Scheme)
            $lbl = [System.Activator]::CreateInstance($labelType)
            $lbl.Text = $Text
            $lbl.X = $posAbsolute.Invoke($null, @($X))
            $lbl.Y = $posAbsolute.Invoke($null, @(0))
            $lbl.Width = $dimAbsolute.Invoke($null, @([Math]::Max(1, $W)))
            $lbl.Height = $dimAbsolute.Invoke($null, @(1))
            [void]$lbl.SetScheme($Scheme)
            return $lbl
        }

        $dot = New-RowLabel -X $geo.DotX -W $geo.DotWidth -Text '' -Scheme $Theme.Unknown
        $name = New-RowLabel -X $geo.NameX -W $geo.NameWidth -Text '' -Scheme $Theme.Text
        $group = New-RowLabel -X $geo.GroupX -W ([Math]::Max(1, $geo.GroupWidth)) -Text '' -Scheme $Theme.Dim
        $tags = New-RowLabel -X $geo.TagsX -W ([Math]::Max(1, $geo.TagsWidth)) -Text '' -Scheme $Theme.Accent
        $time = New-RowLabel -X $geo.TimeX -W $geo.TimeWidth -Text '' -Scheme $Theme.Dim
        # 最后活跃右对齐(列宽固定 6, 文案 '—'/'刚刚'/'12m'/'3d' 都放得下)
        try {
            $alignType = $labelType.GetProperty('TextAlignment').PropertyType
            $time.TextAlignment = [Enum]::Parse($alignType, 'End')
        } catch {
            Write-Verbose "[New-SshHostListView] 时间列右对齐设置失败: $($_.Exception.Message)"
        }

        foreach ($lbl in @($bg, $dot, $name, $group, $tags, $time)) { [void]$rowView.Add($lbl) }
        [void]$container.Add($rowView)

        $slots.Add([PSCustomObject]@{
                Index  = $i
                View   = $rowView
                Bg     = $bg
                Dot    = $dot
                Name   = $name
                Group  = $group
                Tags   = $tags
                Time   = $time
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
        Geometry      = (Get-SshHostListGeometry -Width $Width)
    }

    # 首帧填充: 选中行先滚到可视区(选中优先保证可见)
    if ($SelectedIndex -ge 0 -and $SelectedIndex -lt $listView.Rows.Count) {
        $top = [Math]::Max(0, $SelectedIndex - [int][Math]::Floor($Height / 2))
        $listView.Top = [Math]::Min($top, [Math]::Max(0, $listView.Rows.Count - $Height))
    }
    Set-SshHostListScroll -ListView $listView

    return $listView
}

function Set-SshHostListSlot {
    <#
    .SYNOPSIS
        把一个槽位填成指定行(文本 + 配色); 空行则清空。

    .PARAMETER ListView
        New-SshHostListView 产物(会被就地更新 RowIndex)。

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
        # 空格位: 背景用正文方案(黑底)把缩放/过滤后的残影擦掉
        $slot.Bg.Text = (' ' * $ListView.Width)
        [void]$slot.Bg.SetScheme($theme.Text)
        $slot.Dot.Text = ''
        [void]$slot.Dot.SetScheme($theme.Unknown)
        $slot.Name.Text = ''
        [void]$slot.Name.SetScheme($theme.Text)
        $slot.Group.Text = ''
        [void]$slot.Group.SetScheme($theme.Dim)
        $slot.Tags.Text = ''
        [void]$slot.Tags.SetScheme($theme.Accent)
        $slot.Time.Text = ''
        [void]$slot.Time.SetScheme($theme.Dim)
        return
    }

    $row = $ListView.Rows[$RowIndex]

    # ---- 背景条 + 各行配色(选中态换"紫底"配套方案) ----
    [void]$slot.Bg.SetScheme($(if ($Selected) { $theme.Selected } else { $theme.Text }))

    $dotScheme = switch ($row.StatusRole) {
        'Online' { if ($Selected) { $theme.SelectedOnline } else { $theme.Online } }
        'Offline' { if ($Selected) { $theme.SelectedOffline } else { $theme.Offline } }
        default { if ($Selected) { $theme.SelectedUnknown } else { $theme.Unknown } }
    }
    $slot.Dot.Text = [string]$row.StatusGlyph
    [void]$slot.Dot.SetScheme($dotScheme)

    $indent = if ($row.Indent) { '  ' } else { '' }
    $nameText = Get-SshHostListClip -Text ($indent + [string]$row.Name) -Width $geo.NameWidth
    $slot.Name.Text = $nameText
    [void]$slot.Name.SetScheme($(if ($Selected) { $theme.Selected } else { $theme.Text }))

    $groupText = ''
    if (-not [string]::IsNullOrWhiteSpace([string]$row.Group)) {
        $groupText = Get-SshHostListClip -Text ([string][char]0x25B8 + [string]$row.Group) -Width ([Math]::Max(1, $geo.GroupWidth))
    }
    $slot.Group.Text = $groupText
    [void]$slot.Group.SetScheme($(if ($Selected) { $theme.SelectedMeta } else { $theme.Dim }))

    $tagText = ''
    if ($row.Tags -and @($row.Tags).Count -gt 0) {
        $tagText = (@($row.Tags) | ForEach-Object { '#' + $_ }) -join ' '
        $tagText = Get-SshHostListClip -Text $tagText -Width ([Math]::Max(1, $geo.TagsWidth))
    }
    $slot.Tags.Text = $tagText
    [void]$slot.Tags.SetScheme($(if ($Selected) { $theme.SelectedMeta } else { $theme.Accent }))

    $slot.Time.Text = Get-SshHostListClip -Text ([string]$row.LastActiveText) -Width $geo.TimeWidth
    [void]$slot.Time.SetScheme($(if ($Selected) { $theme.SelectedDim } else { $theme.Dim }))
}

function Update-SshHostListSelection {
    <#
    .SYNOPSIS
        移动选中行 —— **只**重刷旧/新两行(键盘热路径, 不重建 View)。

    .DESCRIPTION
        选中变化只影响两行的配色, 因此这里只调用这两行槽位的 Set-SshHostListSlot
        (改 Label 的 Text/Scheme), 让 TG 的脏区机制只重画这两行。
        越界/相同下标直接返回(幂等)。

    .PARAMETER ListView
        New-SshHostListView 产物。

    .PARAMETER OldIndex
        原选中行下标(-1 = 无)。

    .PARAMETER NewIndex
        新选中行下标(-1 = 无)。

    .OUTPUTS
        [bool] 是否真的发生了重绘(供编排层记录性能日志)。
    #>
    # 纯内存视图刷新(不改变系统状态) —— 抑制 PSSA 的 ShouldProcess 规则
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
        Set-SshHostListSlot -ListView $ListView -SlotIndex $slotIdx -RowIndex $idx -Selected $selected
        $changed = $true
    }
    return $changed
}

function Set-SshHostListScroll {
    <#
    .SYNOPSIS
        把可见窗口滚到指定 Top 并重填全部槽位(滚动/过滤/分类切换时用)。

    .PARAMETER ListView
        New-SshHostListView 产物。

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
    $maxTop = [Math]::Max(0, $ListView.Rows.Count - $ListView.Height)
    if ($ListView.Top -gt $maxTop) { $ListView.Top = $maxTop }
    if ($ListView.Top -lt 0) { $ListView.Top = 0 }

    for ($i = 0; $i -lt $ListView.Slots.Count; $i++) {
        $rowIndex = $ListView.Top + $i
        if ($rowIndex -ge $ListView.Rows.Count) { $rowIndex = -1 }
        $selected = ($rowIndex -ge 0 -and $rowIndex -eq $ListView.SelectedIndex)
        # ★ 只重填**内容真的变了**的槽位: Set-SshHostListSlot 会改 Label 的
        #   Text/Scheme, 两者都会把该 Label 标脏 —— 逐槽比对后跳过没变的,
        #   滚动一行的脏区就从"整屏"缩回"进出的那两行"。
        $slot = $ListView.Slots[$i]
        if ($slot.RowIndex -eq $rowIndex -and $slot.Selected -eq $selected) { continue }
        Set-SshHostListSlot -ListView $ListView -SlotIndex $i -RowIndex $rowIndex -Selected $selected
    }
}

function Sync-SshHostListRow {
    <#
    .SYNOPSIS
        某一行数据变化后(远端状态/最后活跃回填)只重刷它所在的槽位。

    .DESCRIPTION
        异步探测结果回来时调用: 只重画命中的那一行, 其它行保持不动。
        行不在可见窗口内则什么都不做(滚动时自然会带上新内容)。

    .PARAMETER ListView
        New-SshHostListView 产物。

    .PARAMETER RowIndex
        发生变化的行下标。
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$ListView,

        [Parameter(Mandatory = $true)]
        [int]$RowIndex
    )

    if ($RowIndex -lt 0 -or $RowIndex -ge $ListView.Rows.Count) { return }
    $slotIdx = $RowIndex - $ListView.Top
    if ($slotIdx -lt 0 -or $slotIdx -ge $ListView.Slots.Count) { return }
    Set-SshHostListSlot -ListView $ListView -SlotIndex $slotIdx -RowIndex $RowIndex `
        -Selected ($RowIndex -eq $ListView.SelectedIndex)
}

function Set-SshHostListRowFocus {
    <#
    .SYNOPSIS
        设置/取消列表容器的焦点并同步"聚焦态"选中边框效果。

    .DESCRIPTION
        列表与右侧详情/搜索框之间用 Tab 切焦点。焦点在别处时, 选中行仍然
        有紫底(用户始终知道选的是哪台), 但不再额外强调 —— 本函数只负责
        SetFocus, 视觉差异由主题的 Selected 方案统一承担。

    .PARAMETER ListView
        New-SshHostListView 产物。

    .PARAMETER Focus
        $true 聚焦列表; $false 不主动抢焦点(交给别的控件)。
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$ListView,

        [Parameter(Mandatory = $false)]
        [bool]$Focus = $true
    )

    if (-not $Focus) { return }
    try {
        [void]$ListView.View.SetFocus()
    } catch {
        Write-Verbose "[Set-SshHostListRowFocus] 聚焦列表失败: $($_.Exception.Message)"
    }
}
