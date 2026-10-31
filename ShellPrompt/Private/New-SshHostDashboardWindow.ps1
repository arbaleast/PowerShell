# New-SshHostDashboardWindow.ps1 - SSH 主机仪表盘的**整窗组装**(视图层)
#
# 背景 (2026-10-31 sss 仪表盘重构, Goal 二):
#   把主机选择从"普通单表格"升级为多区域仪表盘:
#     行 0        标题带: 左=产品标识 + 主机数; 右=上次使用的主机(右对齐)
#     行 1        分类导航: All / <实际 Provider…> / Local / Other(当前分类高亮)
#     行 2..H-3   主体区: 左主机列表 | 竖向分隔线 | 右详情卡片
#     行 H-2      信息/搜索行: 搜索态显示输入框, 否则显示"筛选/计数/加载"状态
#     行 H-1      底部快捷键栏(单个 Label, 贴底一行)
#
# ★ 窄屏响应式(Goal 七 UI: 窗口调整大小后布局正常):
#   终端 < 72 列时**收起右侧详情**, 列表吃满整宽(详情里的信息在这种宽度下
#   本来就会截断成不可读); 72 列以上按 50% 左右分栏; >= 100 列给列表 56 列
#   (再宽也只是把详情拉宽, 列表超过 56 列后信息密度不再提升)。
#   高度不足时由 Get-SshHostDetailCardPlan 逐张收起卡片(见该函数)。
#
# ★ 全部视图都显式 SetScheme: TG 内置 'Base' 方案是**白对白**(前=背景=白),
#   不绑方案的话窗口底是白的、字迹隐形(2026-10-30 真机教训, 见 tui-dashboard.md §2.9)。
#
# ★ 快捷键栏是**纯展示件**: 键位语义全部由编排层挂的 KeyDown 处理器实现
#   (方向键/Enter///Tab/Esc), 这样只有一条键位事实来源, 不会出现
#   "底栏写着 / 搜索但按了没反应"或"按一次触发两次"的分裂。
#   底栏是**单个 Label** 而不是 StatusBar+Shortcut —— TG 的 Shortcut 用
#   `Key.ToString()` 渲染键名, 没有 '/' 与 '↑↓' 这种键(详见下方注释)。
#
# 契约: 只组装(无头可测) —— 不进事件循环、不读数据源、不做业务分发。

function New-SshHostDashboardWindow {
    <#
    .SYNOPSIS
        按行视图模型组装 SSH 主机仪表盘整窗(无头可测, 不 Run)。

    .DESCRIPTION
        返回对象里带齐编排层要用的句柄:
          Window / ListView / DetailPanel / Categories(标签数组) /
          TitleLabel / CountLabel / InfoLabel / SearchPrompt / SearchField /
          StatusBar / Shortcuts / Layout

    .PARAMETER Rows
        行视图模型数组(Get-SshHostDashboardRow 产物)。

    .PARAMETER Title
        标题带左半文本。

    .PARAMETER Categories
        分类名数组(All 开头; 由数据层 Get-SshHostCategoryList 给出)。

    .PARAMETER ActiveCategory
        当前分类名(必须在 Categories 里)。

    .PARAMETER SelectedIndex
        选中行下标(-1 = 无)。

    .PARAMETER InfoText
        信息行文本(非搜索态显示)。

    .PARAMETER SearchText
        搜索框回填文本。

    .PARAMETER SearchActive
        是否处于搜索态(为真时信息行换成输入框)。

    .PARAMETER LastHostText
        标题带右半文本(上次使用的主机; 空则不显示)。

    .PARAMETER WindowWidth
        终端宽度(默认 120)。

    .PARAMETER WindowHeight
        终端高度(默认 35)。

    .OUTPUTS
        [PSCustomObject] 见 .DESCRIPTION。

    .EXAMPLE
        $win = New-SshHostDashboardWindow -Rows $rows -Title 'SSH 主机 · 12 台' -Categories $cats `
            -ActiveCategory 'All' -SelectedIndex 0 -Theme $theme
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [object[]]$Rows = @(),

        [Parameter(Mandatory = $false)]
        [string]$Title = 'ShellPrompt · SSH Hosts',

        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [string[]]$Categories = @('All'),

        [Parameter(Mandatory = $false)]
        [string]$ActiveCategory = 'All',

        [Parameter(Mandatory = $false)]
        [int]$SelectedIndex = -1,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$InfoText = '',

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$SearchText = '',

        [Parameter(Mandatory = $false)]
        [bool]$SearchActive = $false,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$LastHostText = '',

        [Parameter(Mandatory = $true)]
        [object]$Theme,

        [Parameter(Mandatory = $false)]
        [ValidateRange(20, 1000)]
        [int]$WindowWidth = 120,

        [Parameter(Mandatory = $false)]
        [ValidateRange(6, 1000)]
        [int]$WindowHeight = 35
    )

    if ($PSCmdlet.ShouldProcess('SSH 主机仪表盘窗口', 'Construct')) { } else { return $null }

    $tg = Get-TguiContext
    $static = [System.Reflection.BindingFlags]'Public,Static'
    $posAbsolute = $tg.Types.Pos.GetMethods($static) |
        Where-Object { $_.Name -eq 'Absolute' -and $_.GetParameters().Count -eq 1 } |
        Select-Object -First 1
    $dimAbsolute = $tg.Types.Dim.GetMethods($static) |
        Where-Object { $_.Name -eq 'Absolute' -and $_.GetParameters().Count -eq 1 } |
        Select-Object -First 1
    $labelType = $tg.Types.Label

    function New-DashLabel {
        param([int]$X, [int]$Y, [int]$W, [int]$H, [string]$Text, [object]$Scheme, [string]$Align = '')
        $lbl = [System.Activator]::CreateInstance($labelType)
        $lbl.Text = $Text
        $lbl.X = $posAbsolute.Invoke($null, @($X))
        $lbl.Y = $posAbsolute.Invoke($null, @($Y))
        $lbl.Width = $dimAbsolute.Invoke($null, @([Math]::Max(1, $W)))
        $lbl.Height = $dimAbsolute.Invoke($null, @([Math]::Max(1, $H)))
        [void]$lbl.SetScheme($Scheme)
        if ($Align) {
            try {
                $alignType = $labelType.GetProperty('TextAlignment').PropertyType
                $lbl.TextAlignment = [Enum]::Parse($alignType, $Align)
            } catch {
                Write-Verbose "[New-SshHostDashboardWindow] 文本对齐设置失败: $($_.Exception.Message)"
            }
        }
        return $lbl
    }

    # ---- 布局几何(行分配与分栏; 缩放时整窗重建, 几何按新尺寸重算) ----
    $titleRow = 0
    $categoryRow = 1
    $bodyRow = 2
    $infoRow = [Math]::Max($bodyRow + 1, $WindowHeight - 2)
    $statusRow = $WindowHeight - 1
    $bodyHeight = [Math]::Max(1, $infoRow - $bodyRow)
    # 分栏: 窄屏(<72)收起详情; 72-99 各一半; >=100 列表固定 56
    $showDetail = ($WindowWidth -ge 72)
    if ($showDetail) {
        if ($WindowWidth -ge 100) { $listWidth = 56 }
        else { $listWidth = [int][Math]::Floor($WindowWidth * 0.5) }
        $listWidth = [Math]::Max(34, [Math]::Min($listWidth, $WindowWidth - 30))
        $dividerX = $listWidth + 1
        $detailX = $listWidth + 3
        $detailWidth = $WindowWidth - $detailX
        if ($detailWidth -lt 24) { $showDetail = $false }
    }
    if (-not $showDetail) {
        $listWidth = $WindowWidth
        $dividerX = -1
        $detailX = -1
        $detailWidth = 0
    }

    # ---- 整窗容器 ----
    $window = [System.Activator]::CreateInstance($tg.Types.Window)
    $window.BorderStyle = $null
    [void]$window.SetScheme($Theme.Text)

    # ---- 行 0: 标题带(左标题 / 右上次使用) ----
    $rightText = $LastHostText
    $rightWidth = 0
    if ($rightText) { $rightWidth = (Get-TguiTextWidth -Text $rightText) + 2 }
    $leftWidth = [Math]::Max(1, $WindowWidth - $rightWidth)
    $titleLabel = New-DashLabel -X 0 -Y $titleRow -W $leftWidth -H 1 -Text (Get-SshHostListClip -Text $Title -Width $leftWidth) -Scheme $Theme.TitleBand
    [void]$window.Add($titleLabel)
    $countLabel = $null
    if ($rightText) {
        $countLabel = New-DashLabel -X $leftWidth -Y $titleRow -W ([Math]::Max(1, $rightWidth)) -H 1 `
            -Text $rightText -Scheme $Theme.Dim -Align 'End'
        [void]$window.Add($countLabel)
    }

    # ---- 行 1: 分类导航(每个分类一个 Label, 当前分类用紫底高亮"色块") ----
    $categoryLabels = [System.Collections.Generic.List[object]]::new()
    $x = 1
    foreach ($cat in @($Categories)) {
        $display = [string]$cat
        # 左右各留 1 空格形成"色块"观感(高亮项靠底色区分)
        $labelText = " $display "
        $labelWidth = Get-TguiTextWidth -Text $labelText
        if ($x + $labelWidth -gt $WindowWidth) { break }   # 窄屏只显示放得下的分类
        $isActive = ($display -eq $ActiveCategory)
        $scheme = if ($isActive) { $Theme.CategoryActive } else { $Theme.Category }
        $lbl = New-DashLabel -X $x -Y $categoryRow -W $labelWidth -H 1 -Text $labelText -Scheme $scheme
        [void]$window.Add($lbl)
        $categoryLabels.Add([PSCustomObject]@{ Name = $display; Label = $lbl; X = $x; Width = $labelWidth })
        $x += $labelWidth
    }

    # ---- 主体区: 左列表 ----
    $listView = New-SshHostListView -Rows $Rows -Width $listWidth -Height $bodyHeight `
        -SelectedIndex $SelectedIndex -Theme $Theme -Tgui $tg
    $listView.View.X = $posAbsolute.Invoke($null, @(0))
    $listView.View.Y = $posAbsolute.Invoke($null, @($bodyRow))
    [void]$window.Add($listView.View)

    # ---- 主体区: 竖向分隔线(只做视觉分区, 不参与焦点/键盘) ----
    $divider = $null
    if ($dividerX -ge 0 -and $bodyHeight -gt 0) {
        $dividerText = (@([string][char]0x2502) * $bodyHeight) -join "`n"
        $divider = New-DashLabel -X $dividerX -Y $bodyRow -W 1 -H $bodyHeight -Text $dividerText -Scheme $Theme.Divider
        [void]$window.Add($divider)
    }

    # ---- 主体区: 右侧详情卡片 ----
    $detailPanel = $null
    if ($showDetail) {
        $hasInfra = $false
        foreach ($r in @($Rows)) {
            if ($r.Provider -or $r.Region) { $hasInfra = $true; break }
        }
        $detailPanel = New-SshHostDetailPanel -Width $detailWidth -Height $bodyHeight `
            -HasInfrastructure $hasInfra -Theme $Theme -Tgui $tg
        $detailPanel.View.X = $posAbsolute.Invoke($null, @($detailX))
        $detailPanel.View.Y = $posAbsolute.Invoke($null, @($bodyRow))
        [void]$window.Add($detailPanel.View)
    }

    # ---- 行 H-2: 信息行 / 搜索框(同一行两种形态, 靠 Visible 切换) ----
    $infoLabel = New-DashLabel -X 0 -Y $infoRow -W $WindowWidth -H 1 `
        -Text (Get-SshHostListClip -Text $InfoText -Width $WindowWidth) -Scheme $Theme.Hint
    [void]$window.Add($infoLabel)

    $searchPrompt = New-DashLabel -X 1 -Y $infoRow -W 8 -H 1 -Text '搜索: ' -Scheme $Theme.Accent
    $searchType = $tg.Assembly.GetExportedTypes() |
        Where-Object { $_.FullName -eq 'Terminal.Gui.Views.TextField' } |
        Select-Object -First 1
    if ($null -eq $searchType) {
        throw 'TGUI 载入失败: 缺少 Terminal.Gui.Views.TextField(vendored 版本可能已变更)。'
    }
    $searchField = [System.Activator]::CreateInstance($searchType)
    $searchField.X = $posAbsolute.Invoke($null, @(9))
    $searchField.Y = $posAbsolute.Invoke($null, @($infoRow))
    $searchField.Width = $dimAbsolute.Invoke($null, @([Math]::Max(4, $WindowWidth - 10)))
    $searchField.Height = $dimAbsolute.Invoke($null, @(1))
    $searchField.Text = $SearchText
    $searchField.CanFocus = $true
    [void]$searchField.SetScheme($Theme.Text)
    $searchPrompt.Visible = $SearchActive
    $searchField.Visible = $SearchActive
    $infoLabel.Visible = -not $SearchActive
    [void]$window.Add($searchPrompt)
    [void]$window.Add($searchField)

    # ---- 行 H-1: 底部快捷键栏(纯展示 Label; 键位由编排层的 KeyDown 处理器实现) ----
    # ★ 为什么用 Label 而不是 StatusBar+Shortcut(2026-10-31 反射实测):
    #   TG 2.4.10 的 Shortcut 用 `Key.ToString()` 渲染键名, 而 Key 的静态属性
    #   只有 A-Z / D0-D9 / 导航键 —— **没有** '/' 这种符号键, 也没有 '↑↓'
    #   这种组合键(Key(string) 构造对多字符串直接抛 "Invalid key string")。
    #   用 StatusBar 只能把该项退化成一个真实键(如 Esc), 于是底栏会把
    #   "↑↓ 选择主机" 渲染成 "Esc 选择主机" —— 底栏与真实键位**不一致**。
    #   Label 让我们**逐字**写出 Goal 要求的键位清单, 并且能自己算宽度预算
    #   (StatusBar 不换行, 放不下就在右端硬截断, 见 tui-dashboard.md §2.4)。
    $shortcutDefs = @(Get-SshHostShortcutDef -Area $(if ($SearchActive) { 'Search' } else { 'List' }))
    $shortcutText = Get-SshHostShortcutText -Defs $shortcutDefs -Width $WindowWidth
    $shortcutBar = New-DashLabel -X 0 -Y $statusRow -W $WindowWidth -H 1 -Text $shortcutText -Scheme $Theme.Hint
    [void]$window.Add($shortcutBar)
    $selectedDefs = @($shortcutDefs | Where-Object { $shortcutText.Contains([string]$_.Key) })

    $layout = [PSCustomObject]@{
        TitleRow    = $titleRow
        CategoryRow = $categoryRow
        BodyRow     = $bodyRow
        BodyHeight  = $bodyHeight
        ListWidth   = $listWidth
        DividerX    = $dividerX
        DetailX     = $detailX
        DetailWidth = $detailWidth
        ShowDetail  = $showDetail
        InfoRow     = $infoRow
        StatusRow   = $statusRow
    }

    return [PSCustomObject]@{
        Window        = $window
        ListView      = $listView
        DetailPanel   = $detailPanel
        CategoryBar   = $categoryLabels.ToArray()
        TitleLabel    = $titleLabel
        CountLabel    = $countLabel
        InfoLabel     = $infoLabel
        SearchPrompt  = $searchPrompt
        SearchField   = $searchField
        ShortcutBar   = $shortcutBar
        ShortcutDefs  = $selectedDefs
        Layout        = $layout
        Theme         = $Theme
    }
}

function Get-SshHostShortcutDef {
    <#
    .SYNOPSIS
        返回某个焦点区域下的底部快捷键定义(键位事实来源, 纯函数)。

    .DESCRIPTION
        列表焦点与搜索焦点的键位**不同**, 底栏必须随焦点切换 ——
        否则就会出现"底栏写着 / 搜索但按了没反应"或"写着 Enter 连接,
        实际是 Enter 应用过滤"的分裂(Goal 三-4 要求键位与实际行为一致)。

        字段语义:
          Priority = **被舍掉的顺序**(数字小 = 更重要 = 更晚被舍掉)
          Order     = **显示顺序**

        `Esc` 在列表态的 Priority 特意排在第二位: 它是本仪表盘**唯一**的退出键
        (没有 Q 键), 窄屏下必须比 / Tab ←→ 更晚被舍掉 ——
        "用户看不到怎么退出是不可接受的"(与 tui-dashboard.md §2.4 同源规则)。

    .PARAMETER Area
        'List' | 'Search'。

    .OUTPUTS
        定义数组(每项含 Key / Label / Priority / Order)。
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('List', 'Search')]
        [string]$Area
    )

    if ($Area -eq 'Search') {
        return @(
            [PSCustomObject]@{ Key = 'Enter'; Label = '应用'; Priority = 1; Order = 1 }
            [PSCustomObject]@{ Key = 'Esc'; Label = '取消'; Priority = 2; Order = 3 }
            [PSCustomObject]@{ Key = 'Tab'; Label = '返回列表'; Priority = 3; Order = 2 }
        )
    }

    return @(
        [PSCustomObject]@{ Key = 'Enter'; Label = '连接'; Priority = 1; Order = 1 }
        [PSCustomObject]@{ Key = 'Esc'; Label = '退出'; Priority = 2; Order = 5 }
        [PSCustomObject]@{ Key = '↑↓'; Label = '选择主机'; Priority = 3; Order = 4 }
        [PSCustomObject]@{ Key = '/'; Label = '搜索'; Priority = 4; Order = 2 }
        [PSCustomObject]@{ Key = 'Tab'; Label = '切换区域'; Priority = 5; Order = 3 }
        [PSCustomObject]@{ Key = '←→'; Label = '切换分类'; Priority = 6; Order = 6 }
    )
}

function Get-SshHostShortcutText {
    <#
    .SYNOPSIS
        把快捷键定义渲染成底部栏文本, 并按可用宽度**取舍**显示项(纯函数, 可单测)。

    .DESCRIPTION
        渲染形态: `Enter 连接 │ / 搜索 │ Tab 切换区域 │ ↑↓ 选择主机 │ ←→ 切换分类 │ Esc 退出`
          - 项内 = 键名 + 1 空格 + 标签;
          - 项间 = ' │ '(3 列: 空格 + 竖线 + 空格; '│' U+2502 按仓库
            Get-TguiTextWidth 口径算 1 列 —— 与等宽终端的实际渲染一致)。

        宽度取舍: 按 `Priority` 升序挑能放下的项(保持"优先级前缀"语义),
        再按 `Order` 升序渲染。Priority 与 Order 分离的原因: **Priority 数字小
        = 更重要 = 更晚被舍掉**(数字大的先被舍)。Esc 的 Priority 排在第二位
        —— 它是本仪表盘唯一的退出键, 窄屏下必须比 / Tab ←→ 更晚被舍掉;
        但它的**显示顺序**仍在最后(与 Goal 二-4 的清单一致)。

        预算口径: 可用宽 = Width - 1(留 1 列右边距), 与既有工厂同源。

    .PARAMETER Defs
        快捷键定义数组, 每项含 Key / Label / Priority / Order。

    .PARAMETER Width
        可用列宽。

    .OUTPUTS
        [string] 渲染后的底栏文本(一定放得下, 不会超出 Width)。

    .EXAMPLE
        Get-SshHostShortcutText -Defs $defs -Width 120
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [object[]]$Defs = @(),

        [Parameter(Mandatory = $true)]
        [int]$Width
    )

    if (-not $Defs -or @($Defs).Count -eq 0) { return '' }

    $separator = ' │ '
    $separatorWidth = 3
    $budget = [Math]::Max(0, $Width - 1)

    # ---- 1. 按优先级挑能放下的项 ----
    $chosen = [System.Collections.Generic.List[object]]::new()
    $used = 0
    foreach ($def in (@($Defs) | Sort-Object -Property Priority)) {
        $cost = (Get-TguiTextWidth -Text ([string]$def.Key)) + 1 + (Get-TguiTextWidth -Text ([string]$def.Label))
        $total = if ($chosen.Count -eq 0) { $cost } else { $used + $separatorWidth + $cost }
        if ($total -gt $budget) {
            # 放不下就停: 保持"优先级前缀"语义, 不让低优先级的窄项插队
            if ($chosen.Count -eq 0) {
                # 连第一项都放不下(极窄终端): 至少给一项, 由调用方裁剪
                $chosen.Add($def)
            }
            break
        }
        $chosen.Add($def)
        $used = $total
    }

    # ---- 2. 按显示序渲染 ----
    $parts = @($chosen | Sort-Object -Property Order | ForEach-Object {
            '{0} {1}' -f [string]$_.Key, [string]$_.Label
        })
    $text = ($parts -join $separator)

    # ---- 3. 兜底裁剪(理论上不会触发, 但绝不返回超宽文本) ----
    return (Get-SshHostListClip -Text $text -Width $Width)
}
