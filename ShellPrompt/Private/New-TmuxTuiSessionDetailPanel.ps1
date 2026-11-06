# New-TmuxTuiSessionDetailPanel.ps1 - tmux 会话仪表盘的**右侧会话工作区**(三段式)
#
# 背景 (2026-11-06 阶段一 · 视觉层级与工作区布局重构):
#   旧实现是一张 `FrameView`(标题 " Session ")+ 4 行键值(Session/Status/
#   Windows/No)。真机取证暴露三个问题:
#     1. **双重竖线**: 左侧列表自带右分隔竖线, 右侧 FrameView 又套一层
#        四周边框 —— 中间出现两条平行的长竖线, 视觉噪音大;
#     2. **85% 空白**: 框内只有 4 行基础属性, 其余区域完全空着;
#     3. **信息层级缺失**: 4 个键值行平铺, 没有"概览 / 窗口 / 操作"的分区。
#
# 新实现: **无外框**的三段式工作区(只用彩色区块小标题 + 细分隔线 + 空行分层):
#   ① SESSION OVERVIEW  会话名(主视觉) + 状态徽标 + Session Index / Windows / Host
#   ② WINDOWS           窗口数结构化摘要 + "按 Enter 附着并管理窗格"提示
#                        (阶段二在此无缝替换为真实 `tmux list-windows` 列表)
#   ③ ACTIONS           针对当前会话的高频操作指引卡(纯展示, 不新增键位)
#
# 数据来源纪律: 只用**真实**字段(Get-TmuxSessions 只给会话名 / attached 状态 /
#   窗口数 / 行号); 主机名由编排层注入。没有数据就显示 '—', 绝不为了填满
#   卡片而伪造(不编造"运行时长 / 客户端数"这类没有的数据源)。
#
# 契约: 组装(无头可测) + 就地更新(改 Label.Text 只重画该标签)。

function New-TmuxTuiSessionDetailPanel {
    <#
    .SYNOPSIS
        组装 tmux 会话工作区(三段式, 无外框)。

    .DESCRIPTION
        控件树(全部是普通 View/Label, **没有 FrameView**):
          View (容器 View)
            └─ Section ① SESSION OVERVIEW
                 SectionTitle / SessionName / StatusBadge
                 OverviewIndex / OverviewWindows / OverviewHost
            ├─ Section ② WINDOWS
                 SectionTitle / WindowsSummary / WindowsHint
            └─ Section ③ ACTIONS
                 SectionTitle / ActionKeys(4 行)

        返回对象里带全部**值 Label** 的句柄, 供 Set-TmuxTuiSessionDetail
        就地更新文本(改 Label.Text 只重画该标签, 不重建视图)。

    .PARAMETER Width
        工作区宽度(列)。

    .PARAMETER Height
        工作区高度(行)。

    .PARAMETER HostName
        当前 SSH 主机名(显示在概览的 Host 行; 留空则显示 '—')。

    .PARAMETER Theme
        Get-TuiDashboardTheme 产物(与 SSH 主机仪表盘共用同一套语义 Scheme)。

    .PARAMETER Tgui
        Get-TguiContext 产物。

    .OUTPUTS
        [PSCustomObject] View/Labels(哈希表)/Sections/Width/Height/Theme/Tgui

    .EXAMPLE
        $panel = New-TmuxTuiSessionDetailPanel -Width 60 -Height 30 -Theme $theme -Tgui $tg
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateRange(20, 500)]
        [int]$Width,

        [Parameter(Mandatory = $true)]
        [ValidateRange(4, 200)]
        [int]$Height,

        [Parameter(Mandatory = $false)]
        [string]$HostName = '',

        [Parameter(Mandatory = $true)]
        [object]$Theme,

        [Parameter(Mandatory = $true)]
        [object]$Tgui
    )

    if ($PSCmdlet.ShouldProcess('tmux 会话工作区', 'Construct')) { } else { return $null }

    $static = [System.Reflection.BindingFlags]'Public,Static'
    $posAbsolute = $Tgui.Types.Pos.GetMethods($static) |
        Where-Object { $_.Name -eq 'Absolute' -and $_.GetParameters().Count -eq 1 } |
        Select-Object -First 1
    $dimAbsolute = $Tgui.Types.Dim.GetMethods($static) |
        Where-Object { $_.Name -eq 'Absolute' -and $_.GetParameters().Count -eq 1 } |
        Select-Object -First 1
    $labelType = $Tgui.Types.Label
    $viewType = $Tgui.Types.View

    # 容器: 普通 View(不是 FrameView) —— 没有边框, 就没有"双重竖线"
    $container = [System.Activator]::CreateInstance($viewType)
    $container.X = $posAbsolute.Invoke($null, @(0))
    $container.Y = $posAbsolute.Invoke($null, @(0))
    $container.Width = $dimAbsolute.Invoke($null, @($Width))
    $container.Height = $dimAbsolute.Invoke($null, @($Height))
    [void]$container.SetScheme($Theme.Card)

    # 键列宽 12 + 1 空格; 值列吃满剩余
    $keyX = 0
    $keyWidth = 12
    $valueX = $keyX + $keyWidth + 1
    $valueWidth = [Math]::Max(6, $Width - $valueX)

    $labels = @{}
    $sections = [System.Collections.Generic.List[object]]::new()

    # 视图行分配(自上而下): 每段小标题占 1 行, 内容按行数展开。
    #   行 0 : ① SESSION OVERVIEW 小标题
    #   行 1 : 会话名(主视觉, White)
    #   行 2 : 状态徽标(● Attached 亮绿 / ○ Detached 灰)
    #   行 3 : (空行 —— 段落呼吸)
    #   行 4 : Session Index / Windows / Host 三行属性 —— 行 4,5,6
    #   行 7 : (空行)
    #   行 8 : ② WINDOWS 小标题
    #   行 9 : 窗口数摘要
    #   行 10: 提示(Enter 附着并管理窗格)
    #   行 11: (空行)
    #   行 12: ③ ACTIONS 小标题
    #   行 13..16: 四条操作指引
    # 行高不足时**从下往上**裁剪(先砍 ACTIONS, 再砍 WINDOWS, 概览永远保留)。
    $labelsList = [System.Collections.Generic.List[object]]::new()

    function Add-PanelLabel {
        # 纯视图工厂: 建一个 Label 并挂到容器上(返回句柄)
        param(
            [int]$X,
            [int]$Y,
            [int]$W,
            [string]$Text,
            [object]$Scheme,
            [bool]$RightAlign = $false,
            [bool]$Bold = $false
        )
        $lbl = [System.Activator]::CreateInstance($labelType)
        $lbl.Text = $Text
        $lbl.X = $posAbsolute.Invoke($null, @($X))
        $lbl.Y = $posAbsolute.Invoke($null, @($Y))
        $lbl.Width = $dimAbsolute.Invoke($null, @([Math]::Max(1, $W)))
        $lbl.Height = $dimAbsolute.Invoke($null, @(1))
        [void]$lbl.SetScheme($Scheme)
        if ($RightAlign) {
            try {
                $alignEnum = $labelType.GetProperty('TextAlignment').PropertyType
                $lbl.TextAlignment = [Enum]::Parse($alignEnum, 'End')
            }
            catch { Write-Verbose "[New-TmuxTuiSessionDetailPanel] 右对齐设置失败: $($_.Exception.Message)" }
        }
        if ($Bold) {
            try { $lbl.TextFormatter = $Tgui.Types.TextFormatter  }
            catch { Write-Verbose "[New-TmuxTuiSessionDetailPanel] 粗体设置跳过: $($_.Exception.Message)" }
        }
        [void]$container.Add($lbl)
        $labelsList.Add($lbl)
        return $lbl
    }

    # ---------- ① SESSION OVERVIEW ----------
    $sec1Title = Add-PanelLabel -X 0 -Y 0 -W $Width -Text 'SESSION OVERVIEW' -Scheme $Theme.SectionTitle
    $sec1Name = Add-PanelLabel -X 0 -Y 1 -W $Width -Text '' -Scheme $Theme.Card
    $sec1Badge = Add-PanelLabel -X 0 -Y 2 -W $Width -Text '' -Scheme $Theme.Detached
    $sec1Index = Add-PanelLabel -X $valueX -Y 4 -W $valueWidth -Text '' -Scheme $Theme.Card
    $sec1Windows = Add-PanelLabel -X $valueX -Y 5 -W $valueWidth -Text '' -Scheme $Theme.Card
    $sec1Host = Add-PanelLabel -X $valueX -Y 6 -W $valueWidth -Text '' -Scheme $Theme.Card
    $sec1IndexKey = Add-PanelLabel -X $keyX -Y 4 -W $keyWidth -Text 'Session Index' -Scheme $Theme.Dim
    $sec1WindowsKey = Add-PanelLabel -X $keyX -Y 5 -W $keyWidth -Text 'Windows' -Scheme $Theme.Dim
    $sec1HostKey = Add-PanelLabel -X $keyX -Y 6 -W $keyWidth -Text 'Host' -Scheme $Theme.Dim

    # ---------- ② WINDOWS ----------
    $sec2Title = Add-PanelLabel -X 0 -Y 8 -W $Width -Text 'WINDOWS' -Scheme $Theme.SectionTitle
    $sec2Summary = Add-PanelLabel -X 0 -Y 9 -W $Width -Text '' -Scheme $Theme.Card
    $sec2Hint = Add-PanelLabel -X 0 -Y 10 -W $Width -Text 'Press Enter to attach and manage panes' -Scheme $Theme.Hint

    # ---------- ③ ACTIONS ----------
    $sec3Title = Add-PanelLabel -X 0 -Y 12 -W $Width -Text 'ACTIONS' -Scheme $Theme.SectionTitle
    $actionRows = @(
        [PSCustomObject]@{ Key = 'Enter'; Desc = 'Attach session'; Row = 13 }
        [PSCustomObject]@{ Key = 'n'; Desc = 'New session'; Row = 14 }
        [PSCustomObject]@{ Key = 'r'; Desc = 'Refresh status'; Row = 15 }
        [PSCustomObject]@{ Key = 'x'; Desc = 'Delete session'; Row = 16 }
    )
    $actionKeyLabels = @{}
    $actionDescLabels = @{}
    foreach ($a in $actionRows) {
        $actionKeyLabels[$a.Key] = Add-PanelLabel -X $keyX -Y $a.Row -W $keyWidth -Text $a.Key -Scheme $Theme.AccentCyan
        $actionDescLabels[$a.Key] = Add-PanelLabel -X $valueX -Y $a.Row -W $valueWidth -Text $a.Desc -Scheme $Theme.Subtle
    }

    # 高度不够时**从下往上**裁剪: 优先保住概览段, 再保 WINDOWS, 最后才是 ACTIONS。
    # 裁剪 = 把该 Label 移出容器(TG 的 View.Remove)并清空文本。
    # 判定口径: 该行号 >= 容器高度 => 这一行**画不出来** => 裁掉。
    # 顺序(从最下面的行往上裁)保证"上面保留、下面让位"。
    $orderedByRow = @(
        [PSCustomObject]@{ Row = 16; Labels = @($actionKeyLabels['x'], $actionDescLabels['x']) }
        [PSCustomObject]@{ Row = 15; Labels = @($actionKeyLabels['r'], $actionDescLabels['r']) }
        [PSCustomObject]@{ Row = 14; Labels = @($actionKeyLabels['n'], $actionDescLabels['n']) }
        [PSCustomObject]@{ Row = 13; Labels = @($actionKeyLabels['Enter'], $actionDescLabels['Enter']) }
        [PSCustomObject]@{ Row = 12; Labels = @($sec3Title) }
        [PSCustomObject]@{ Row = 10; Labels = @($sec2Hint) }
        [PSCustomObject]@{ Row = 9; Labels = @($sec2Summary) }
        [PSCustomObject]@{ Row = 8; Labels = @($sec2Title) }
        [PSCustomObject]@{ Row = 6; Labels = @($sec1Host, $sec1HostKey) }
        [PSCustomObject]@{ Row = 5; Labels = @($sec1Windows, $sec1WindowsKey) }
        [PSCustomObject]@{ Row = 4; Labels = @($sec1Index, $sec1IndexKey) }
        [PSCustomObject]@{ Row = 2; Labels = @($sec1Badge) }
        [PSCustomObject]@{ Row = 1; Labels = @($sec1Name) }
        [PSCustomObject]@{ Row = 0; Labels = @($sec1Title) }
    )
    foreach ($grp in $orderedByRow) {
        if ($grp.Row -lt $Height) { continue }
        foreach ($lbl in $grp.Labels) {
            if ($null -eq $lbl) { continue }
            try { [void]$container.Remove($lbl) } catch {
                Write-Verbose "[New-TmuxTuiSessionDetailPanel] 裁剪标签失败: $($_.Exception.Message)"
            }
            $lbl.Text = ''
        }
    }

    $sections.Add([PSCustomObject]@{ Name = 'Overview'; Title = $sec1Title }) | Out-Null
    $sections.Add([PSCustomObject]@{ Name = 'Windows'; Title = $sec2Title }) | Out-Null
    $sections.Add([PSCustomObject]@{ Name = 'Actions'; Title = $sec3Title }) | Out-Null

    # 语义键名 -> Label 句柄(Set-TmuxTuiSessionDetail 用)
    $labels['Session'] = $sec1Name
    $labels['Status'] = $sec1Badge
    $labels['Index'] = $sec1Index
    $labels['Windows'] = $sec1Windows
    $labels['Host'] = $sec1Host
    $labels['WindowsSummary'] = $sec2Summary
    $labels['Actions'] = $sec3Title

    return [PSCustomObject]@{
        View     = $container
        # 旧字段名保留(Card = 容器 View), 以免外部/测试按旧形状取视图时拿到 $null
        Card     = $container
        Labels   = $labels
        Sections = $sections.ToArray()
        ActionKeyLabels   = $actionKeyLabels
        ActionDescLabels  = $actionDescLabels
        # 概览段的键标签(与值标签成对; 暴露出来便于渲染层按需改键名)
        OverviewKeyLabels = @{
            'Session Index' = $sec1IndexKey
            'Windows'       = $sec1WindowsKey
            'Host'          = $sec1HostKey
        }
        # 已应用方案登记(SetScheme 不是幂等 no-op, 等值跳过能缩小脏区)
        AppliedSchemes = @{}
        # 原值登记: 详情区有多个字段, 上下移动时大部分字段的**原值**与上一行
        # 完全相同。截断要逐字符测宽, 先比原值再裁剪可以把按键路径上的
        # 裁剪开销降到 0(与 SSH 详情面板的 RawValues 守卫同构)。
        RawValues = @{}
        # 值列宽登记在此, 更新时按**同一个值**裁剪 —— 两处各算一遍会漂移:
        # 裁剪比值 Label 自身宽时 TG 只能硬切, 长会话名末尾被生硬截断(无省略号)。
        ValueWidth = $valueWidth
        HostName   = $HostName
        Width      = $Width
        Height     = $Height
        Theme      = $Theme
        Tgui       = $Tgui
    }
}

function Set-TmuxTuiSessionDetail {
    <#
    .SYNOPSIS
        把选中会话的真实字段落到工作区(无数据即 '—')。

    .PARAMETER Panel
        New-TmuxTuiSessionDetailPanel 产物。

    .PARAMETER Row
        会话行视图模型(ConvertTo-TmuxTuiViewModel 的 .SessionRows 元素);
        $null = 没有选中会话(全部字段写 '—')。
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Panel,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$Row
    )

    $theme = $Panel.Theme
    # 裁剪宽度取**面板登记的值列宽**(与值 Label 自身宽度同源) —— 两处各算一遍
    # 会漂移: 裁剪比标签宽 2 列时, TG 只能硬切, 长会话名末尾被生硬截断。
    $valueWidth = [Math]::Max(6, [int]$Panel.ValueWidth)

    function Set-DetailValue {
        param([string]$Key, [string]$Text)
        $lbl = $Panel.Labels[$Key]
        if ($null -eq $lbl) { return }
        # ★ 原值未变 -> 连截断都不用算(2026-11 性能审计修复):
        #   裁剪走 Get-SshHostListClip -> Get-TguiTextWidth 逐字符测宽,
        #   是按键路径上最贵的一步; 上下移动时多个字段里通常只有 1~2 个
        #   真的变了。改成"先比原值, 变了才裁剪", 与 SSH 详情面板的
        #   RawValues 守卫(New-SshHostDetailPanel.ps1)同构。
        if ($Panel.RawValues.ContainsKey($Key) -and $Panel.RawValues[$Key] -ceq $Text) { return }
        $Panel.RawValues[$Key] = $Text
        $clipped = Get-SshHostListClip -Text $Text -Width $valueWidth
        if ([string]$lbl.Text -ceq $clipped) { return }
        $lbl.Text = $clipped
    }

    if ($null -eq $Row) {
        foreach ($k in @('Session', 'Status', 'Index', 'Windows', 'Host')) { Set-DetailValue -Key $k -Text '—' }
        # 空态: 徽标与窗口摘要不残留上一个会话的内容
        $badge = $Panel.Labels['Status']
        if ($null -ne $badge) { $badge.Text = '○ no session selected' }
        $summary = $Panel.Labels['WindowsSummary']
        if ($null -ne $summary) { $summary.Text = '— no active window(s)' }
        return
    }

    Set-DetailValue -Key 'Session' -Text ([string]$Row.Session)
    $windows = '—'
    try { $windows = [string][int]$Row.Windows } catch { $windows = '—' }
    Set-DetailValue -Key 'Windows' -Text $windows
    $no = '—'
    try { $no = [string][int]$Row.No } catch { $no = '—' }
    Set-DetailValue -Key 'Index' -Text $no
    # Host: 编排层没传主机名时也是"没有数据" —— 写 '—' 而不是空串,
    # 与"没有数据就显示 '—'"的纪律一致(空串会渲染成一条空行, 看着像漏字)。
    # ★ 变量名不能叫 $host —— PowerShell 的 $Host 是只读自动变量。
    $hostText = '—'
    if (-not [string]::IsNullOrEmpty([string]$Panel.HostName)) { $hostText = [string]$Panel.HostName }
    Set-DetailValue -Key 'Host' -Text $hostText

    # ---- 状态徽标: ● Attached(亮绿) / ○ Detached(灰) ----
    # "符号 + 颜色"双重表达(16 色终端里不靠颜色单独承载语义)。
    $isAttached = ([string]$Row.Status -eq 'Attached')
    $badge = $Panel.Labels['Status']
    if ($null -ne $badge) {
        $badgeText = if ($isAttached) { '● Attached' } else { '○ Detached' }
        if ([string]$badge.Text -cne $badgeText) { $badge.Text = $badgeText }
        $scheme = if ($isAttached) { $theme.Attached } else { $theme.Detached }
        if (-not $Panel.AppliedSchemes.ContainsKey('Status') -or $Panel.AppliedSchemes['Status'] -ne $scheme) {
            [void]$badge.SetScheme($scheme)
            $Panel.AppliedSchemes['Status'] = $scheme
        }
    }

    # ---- 窗口摘要(阶段二预留容器): ● <N> active window(s) in this session ----
    $summary = $Panel.Labels['WindowsSummary']
    if ($null -ne $summary) {
        $count = 0
        try { $count = [int]$Row.Windows } catch { $count = 0 }
        $summaryText = if ($isAttached) {
            "● $count active window(s) in this session"
        }
        else {
            "○ $count window(s) in this session"
        }
        if ([string]$summary.Text -cne $summaryText) { $summary.Text = $summaryText }
    }
}
