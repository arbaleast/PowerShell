# New-TmuxTuiSessionDetailPanel.ps1 - tmux 会话仪表盘的**右侧非对称三区驾驶舱**
#
# 背景 (2026-11-06 #9b871512 "Forest Matrix"):
#   阶段一的实现是"无外框三段式工作区"(SESSION OVERVIEW / WINDOWS / ACTIONS),
#   真机验收暴露了三个问题:
#     1. **Session Index 无意义** —— "#2" 这种行号对用户没有任何价值, 而且
#        "Session Index" 12 列放不下, 被截成 "Session Inde"(阶段一遗留缺陷);
#     2. **Windows: 1 是个死数字** —— 没有内部进程/路径信息, 看不出这个窗口
#        在跑什么、在哪个目录;
#     3. **ACTIONS 与底栏 100% 重复** —— 右侧再列一遍 Enter/n/r/x 是纯噪音,
#        而且它占掉了本该放"真实信息"的宝贵纵向空间。
#
# 新结构(非对称三区):
#   右上区(Top Split Header): 左 SESSION // <name> + State/Host
#                            右 SUMMARY(Created / Windows (Np))
#   右中区(Middle Zone): WINDOWS & ACTIVE PROCESSES
#                        * 0:main (zsh)      1:editor (nvim)
#                          └─ ~/work/hermes    └─ ~/work/src
#   右下区(Bottom Zone): TERMINAL PREVIEW [session:win.pane]  #9b871512
#                        ┌────────────────────────────┐
#                        │ debian@server:~$ git log …  │
#                        └────────────────────────────┘
#
# ★ 关键纪律:
#   - **无 FrameView 外框**: 整个驾驶舱是普通 View, 分区靠竹青色小标题 +
#     DarkGray 细线 + 空行, 不靠边框(消除"双重竖线"与"大空框")。
#   - **只渲染真实数据**: 数据层(ConvertTo-TmuxTuiViewModel)已经把
#     Created/Activity/Windows[]/PreviewLines[] 准备好, 这里只做显示。
#   - **零网络**: 切换会话时只读内存里的 ViewModel 行, 不发任何请求
#     —— 方向键必须零延迟。
#   - **向后兼容**: 老 Mock 数据没有 Windows[]/PreviewLines[] 时优雅降级
#     (显示 "N/A" / "[No preview output available]"), 绝不抛异常。
#
# 契约: 组装(无头可测) + 就地更新(改 Label.Text 只重画该标签)。

function New-TmuxTuiSessionDetailPanel {
    <#
    .SYNOPSIS
        组装 tmux 会话驾驶舱(非对称三区, 无外框)。

    .DESCRIPTION
        控件树(全部普通 View/Label, **没有 FrameView**):
          View (容器 View)
            右上区  TitleLabel("SESSION // <name>") / StateLabel / HostLabel
                    SummaryTitle("SUMMARY") / CreatedLabel / WindowsLabel
                    Separator(── 细分隔线 ──)
            右中区  WinZoneTitle("WINDOWS & ACTIVE PROCESSES")
                    WinRows(每窗口 2 行: 名称行 + 路径行)
            右下区  PreviewTitle("TERMINAL PREVIEW [s:w.p]")
                    PreviewBoxTop / PreviewRows(最多 8 行) / PreviewBoxBottom

        返回对象里带全部**值 Label** 的句柄, 供 Set-TmuxTuiSessionDetail
        就地更新文本(改 Label.Text 只重画该标签, 不重建视图)。

    .PARAMETER Width
        驾驶舱宽度(列)。

    .PARAMETER Height
        驾驶舱高度(行)。

    .PARAMETER HostName
        当前 SSH 主机名(显示在 Host 行; 留空则显示 '—')。

    .PARAMETER Theme
        Get-TuiDashboardTheme 产物(与 SSH 主机仪表盘共用同一套语义 Scheme)。

    .PARAMETER Tgui
        Get-TguiContext 产物。

    .OUTPUTS
        [PSCustomObject] View/Labels(哈希表)/Sections/Width/Height/Theme/Tgui

    .EXAMPLE
        $panel = New-TmuxTuiSessionDetailPanel -Width 80 -Height 30 -Theme $theme -Tgui $tg
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

    if ($PSCmdlet.ShouldProcess('tmux 会话驾驶舱', 'Construct')) { } else { return $null }

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

    $labels = @{}
    $sections = [System.Collections.Generic.List[object]]::new()

    function Add-PanelLabel {
        # 纯视图工厂: 建一个 Label 并挂到容器上(返回句柄)
        param(
            [int]$X,
            [int]$Y,
            [int]$W,
            [string]$Text,
            [object]$Scheme
        )
        $lbl = [System.Activator]::CreateInstance($labelType)
        $lbl.Text = $Text
        $lbl.X = $posAbsolute.Invoke($null, @($X))
        $lbl.Y = $posAbsolute.Invoke($null, @($Y))
        $lbl.Width = $dimAbsolute.Invoke($null, @([Math]::Max(1, $W)))
        $lbl.Height = $dimAbsolute.Invoke($null, @(1))
        [void]$lbl.SetScheme($Scheme)
        [void]$container.Add($lbl)
        return $lbl
    }

    # ---------- 行分配 ----------
    # 右上区(0-2):
    #   行 0  SESSION // <name>          |  SUMMARY
    #   行 1  State: <状态> (Active <x>) |  Created : <相对时间>
    #   行 2  Host : <host>              |  Windows : <N> (<M>p)
    #   行 3  ─────────── 细分隔线 ───────────
    # 右中区(4-):
    #   行 4  WINDOWS & ACTIVE PROCESSES
    #   行 5.. 窗口行(每窗口 2 行: 名称行 + 路径行)
    # 右下区:
    #   行 N   TERMINAL PREVIEW [s:w.p]
    #   行 N+1 ┌───┐
    #   行 N+2.. 内容行(最多 8 行)
    #   行 M   └───┘
    #
    # SUMMARY 与 SESSION 并排的门槛: 右侧宽度 >= 50 列; 窄了就纵向堆叠。
    $wideSummary = ($Width -ge 50)
    $summaryX = if ($wideSummary) { [int][Math]::Floor($Width / 2) } else { 0 }
    $summaryW = if ($wideSummary) { $Width - $summaryX } else { $Width }
    $sessionW = if ($wideSummary) { $summaryX - 1 } else { $Width }

    $sec1Title = Add-PanelLabel -X 0 -Y 0 -W $sessionW -Text 'SESSION //' -Scheme $Theme.ForestAccent
    $sec1State = Add-PanelLabel -X 0 -Y 1 -W $sessionW -Text '' -Scheme $Theme.Card
    $sec1Host = Add-PanelLabel -X 0 -Y 2 -W $sessionW -Text '' -Scheme $Theme.Card
    $summaryTitle = Add-PanelLabel -X $summaryX -Y 0 -W $summaryW -Text 'SUMMARY' -Scheme $Theme.ForestAccent
    $summaryCreated = Add-PanelLabel -X $summaryX -Y 1 -W $summaryW -Text '' -Scheme $Theme.ForestSummaryVal
    $summaryWindows = Add-PanelLabel -X $summaryX -Y 2 -W $summaryW -Text '' -Scheme $Theme.ForestSummaryVal

    # 细分隔线(DarkGray)—— 用 ─ 铺满整行, 把右上区与右中区隔开。
    # ★ 必须用**字符串**乘法而不是 @(...) 数组乘法: `@([char]0x2500) * 60` 得到的是
    #   一个 60 元素的**数组**, 赋给 Label.Text 时按 $OFS=' ' 拼成 '─ ─ ─ …'
    #   (119 个可见列!), 框线会被撑破。字符串乘法才是连续的实线。
    $separator = Add-PanelLabel -X 0 -Y 3 -W $Width -Text (([string][char]0x2500) * $Width) -Scheme $Theme.ForestFrame

    # ---------- 右中区: WINDOWS & ACTIVE PROCESSES ----------
    $winZoneTitle = Add-PanelLabel -X 0 -Y 4 -W $Width -Text 'WINDOWS & ACTIVE PROCESSES' -Scheme $Theme.ForestAccent
    $winRows = [System.Collections.Generic.List[object]]::new()

    # ---------- 右下区: TERMINAL PREVIEW(贴底) ----------
    # 预览块固定 11 行(标题 1 + 上框 1 + 内容 8 + 下框 1), 锚在面板底部。
    $previewBlockHeight = 11
    $previewTitleRow = [Math]::Max(5, $Height - $previewBlockHeight)
    $previewTitle = Add-PanelLabel -X 0 -Y $previewTitleRow -W $Width -Text '' -Scheme $Theme.ForestAccent
    # 主题标识 #9b871512: 贴在预览标题行**右侧**(DarkGray, 弱化成角标)。
    # 它是纯装饰, 不能抢预览标题的注意力 —— 所以用暗灰而不是竹青。
    # 宽度按 "#9b871512" 的显示宽 + 2 留白, 右对齐到面板右缘;
    # 预览标题的宽度相应收窄, 两片**不重叠**。
    $badgeText = '#9b871512'
    $badgeWidth = (Get-TguiTextWidth -Text $badgeText) + 2
    if ($badgeWidth -gt $Width) { $badgeWidth = 0 }
    $previewBadge = Add-PanelLabel -X 0 -Y $previewTitleRow -W $Width -Text $badgeText -Scheme $Theme.ForestFrame
    if ($badgeWidth -gt 0) {
        $previewBadge.X = $posAbsolute.Invoke($null, @([Math]::Max(0, $Width - $badgeWidth)))
        $previewBadge.Width = $dimAbsolute.Invoke($null, @($badgeWidth))
        $alignEnum = $labelType.GetProperty('TextAlignment').PropertyType
        try { $previewBadge.TextAlignment = [Enum]::Parse($alignEnum, 'End') }
        catch { Write-Verbose "[New-TmuxTuiSessionDetailPanel] 主题角标右对齐失败: $($_.Exception.Message)" }
        # 预览标题收窄, 避免与角标重叠
        $previewTitle.Width = $dimAbsolute.Invoke($null, @([Math]::Max(1, $Width - $badgeWidth)))
    }
    $previewBoxTop = Add-PanelLabel -X 0 -Y ($previewTitleRow + 1) -W $Width -Text '' -Scheme $Theme.ForestPreviewBox
    $previewRows = [System.Collections.Generic.List[object]]::new()
    $previewBoxBottom = Add-PanelLabel -X 0 -Y ($previewTitleRow + 10) -W $Width -Text '' -Scheme $Theme.ForestPreviewBox
    # 预览内容行的起始行号(供 Update-TmuxTuiPreviewBox 复用)
    $previewContentTop = $previewTitleRow + 2

    $sections.Add([PSCustomObject]@{ Name = 'Session'; Title = $sec1Title }) | Out-Null
    $sections.Add([PSCustomObject]@{ Name = 'Summary'; Title = $summaryTitle }) | Out-Null
    $sections.Add([PSCustomObject]@{ Name = 'Windows'; Title = $winZoneTitle }) | Out-Null
    $sections.Add([PSCustomObject]@{ Name = 'Preview'; Title = $previewTitle }) | Out-Null

    # 语义键名 -> Label 句柄(Set-TmuxTuiSessionDetail 用)
    $labels['Session'] = $sec1Title
    $labels['State'] = $sec1State
    $labels['Host'] = $sec1Host
    $labels['Summary'] = $summaryTitle
    $labels['Created'] = $summaryCreated
    $labels['Windows'] = $summaryWindows
    $labels['Preview'] = $previewTitle

    return [PSCustomObject]@{
        View     = $container
        # 旧字段名保留(Card = 容器 View), 以免外部/测试按旧形状取视图时拿到 $null
        Card     = $container
        Labels   = $labels
        Sections = $sections.ToArray()
        WinRows  = $winRows
        PreviewRows = $previewRows
        Separator = $separator
        PreviewBoxTop = $previewBoxTop
        PreviewBoxBottom = $previewBoxBottom
        PreviewBadge = $previewBadge
        # 预览块的行几何(供 Update-TmuxTuiPreviewBox 复用槽位)
        PreviewContentTop = $previewContentTop
        PreviewBlockHeight = $previewBlockHeight
        # 已应用方案登记(SetScheme 不是幂等 no-op, 等值跳过能缩小脏区)
        AppliedSchemes = @{}
        # 原值登记: 详情区有多个字段, 上下移动时大部分字段的**原值**与上一行
        # 完全相同。截断要逐字符测宽, 先比原值再裁剪可以把按键路径上的
        # 裁剪开销降到 0(与 SSH 详情面板的 RawValues 守卫同构)。
        RawValues = @{}
        HostName = $HostName
        Width    = $Width
        Height   = $Height
        Theme    = $Theme
        Tgui     = $Tgui
    }
}

function Set-TmuxTuiSessionDetail {
    <#
    .SYNOPSIS
        把选中会话的真实字段落到驾驶舱(无数据即 '—' / 'N/A')。

    .DESCRIPTION
        字段来源全部是**内存里的 ViewModel 行**(数据层已预转换):
          .Session/.Status/.Windows  —— 基础字段
          .Created/.Activity           —— 相对时间(数据层算好)
          .PaneCount                  —— 窗格总数
          .Windows[]                  —— 窗口拓扑数组(元素含 Index/Name/Active/
                                        Command/Path/PathShort)
          .PreviewLines[]             —— 活动窗格终端输出快照
          .PreviewTarget              —— "session:win.pane" 标签

        老 Mock 数据缺这些字段时优雅降级为 'N/A' / 空列表, 不抛异常。

    .PARAMETER Panel
        New-TmuxTuiSessionDetailPanel 产物。

    .PARAMETER Row
        会话行视图模型; $null = 没有选中会话。
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

    # ★ 原值未变 -> 直接跳过(2026-11 性能审计修复): 裁剪要逐字符测宽, 是
    #   按键路径上最贵的一步; 上下移动时多个字段里通常只有 1~2 个真的变了。
    function Set-RawValue {
        param([string]$Key, [string]$Text)
        $lbl = $Panel.Labels[$Key]
        if ($null -eq $lbl) { return }
        if ($Panel.RawValues.ContainsKey($Key) -and $Panel.RawValues[$Key] -ceq $Text) { return }
        $Panel.RawValues[$Key] = $Text
        if ([string]$lbl.Text -ceq $Text) { return }
        $lbl.Text = $Text
    }

    if ($null -eq $Row) {
        Set-RawValue -Key 'Session' -Text 'SESSION //'
        Set-RawValue -Key 'State' -Text 'State: — (no session selected)'
        Set-RawValue -Key 'Host' -Text 'Host : —'
        Set-RawValue -Key 'Created' -Text 'Created : N/A'
        Set-RawValue -Key 'Windows' -Text 'Windows : N/A'
        Set-RawValue -Key 'Preview' -Text 'TERMINAL PREVIEW'
        Update-TmuxTuiWindowRow -Panel $Panel -Windows @()
        Update-TmuxTuiPreviewBox -Panel $Panel -Lines @('[No preview output available]')
        return
    }

    # ---- 右上区: SESSION // <name> + State / Host ----
    $sessionName = [string]$Row.Session
    Set-RawValue -Key 'Session' -Text ("SESSION // " + $sessionName)

    $isAttached = ([string]$Row.Status -eq 'Attached')
    $statusWord = if ($isAttached) { 'Attached' } else { 'Detached' }
    $statusGlyph = if ($isAttached) { [string][char]0x25CF } else { [string][char]0x25CB }
    $activity = [string]$Row.Activity
    if ([string]::IsNullOrEmpty($activity)) { $activity = 'N/A' }
    # 数据层对 attached 会话给的是 'Active now'(完整短语), 对 detached 给的是
    # 相对时间('5m ago')。两种形态的措辞不同, 这里按内容判断要不要加前缀:
    #   'Active now' -> 直接用, 不重复 "Active "
    #   '5m ago'     -> 加前缀成 "(Active 5m ago)"
    if ($activity -match '(?i)^active\b') {
        Set-RawValue -Key 'State' -Text ("State: $statusGlyph $statusWord ($activity)")
    }
    else {
        Set-RawValue -Key 'State' -Text ("State: $statusGlyph $statusWord (Active $activity)")
    }

    $hostName = [string]$Panel.HostName
    if ([string]::IsNullOrEmpty($hostName)) { $hostName = '—' }
    Set-RawValue -Key 'Host' -Text ("Host : $hostName")

    # ---- 右上区右半: SUMMARY ----
    $created = [string]$Row.Created
    if ([string]::IsNullOrEmpty($created)) { $created = 'N/A' }
    Set-RawValue -Key 'Created' -Text ("Created : $created")

    $winCount = 0
    try { $winCount = [int]$Row.Windows } catch { $winCount = 0 }
    $paneCount = 0
    try { $paneCount = [int]$Row.PaneCount } catch { $paneCount = 0 }
    if ($paneCount -gt 0) {
        Set-RawValue -Key 'Windows' -Text ("Windows : $winCount (${paneCount}p)")
    }
    else {
        Set-RawValue -Key 'Windows' -Text ("Windows : $winCount")
    }

    # ---- 右中区: 窗口拓扑 ----
    # ★ 字段名的坑: SessionRows.Windows 是**窗口数(int)**(列表列 'WINDOWS' 的
    #   既有契约), 窗口拓扑数组在 **WindowList** 里(数据层同时给了
    #   .Windows/.WindowList 两个别名指向同一数组, 但合并行时 .Windows 被
    #   基础行的 int 保留了 —— 所以这里**必须读 WindowList**)。
    # 老 Mock 没有该字段时退化为空数组 -> 右栏显示占位提示。
    $windows = @()
    if ($null -ne $Row.PSObject.Properties['WindowList'] -and $null -ne $Row.WindowList) {
        $windows = @($Row.WindowList)
    }
    Update-TmuxTuiWindowRow -Panel $Panel -Windows $windows

    # ---- 右下区: 终端预览 ----
    $previewLines = @()
    if ($null -ne $Row.PreviewLines) { $previewLines = @($Row.PreviewLines) }
    # 预览标签 "session:win.pane": 数据层没给现成字段时, 从窗口拓扑里
    # 找活动窗口(第一个 Active 的), 退化成 0.0。
    $previewTag = [string]$Row.PreviewTarget
    if ([string]::IsNullOrEmpty($previewTag)) {
        $activeWin = -1
        $wi = 0
        foreach ($w in @($windows)) {
            if ($null -eq $w) { continue }
            $isAct = $false
            try { $isAct = [bool]$w.Active } catch { $isAct = $false }
            if ($isAct) { $activeWin = $wi; break }
            $wi++
        }
        if ($activeWin -lt 0) { $activeWin = 0 }
        $previewTag = "${sessionName}:${activeWin}.0"
    }
    Set-RawValue -Key 'Preview' -Text ("TERMINAL PREVIEW [$previewTag]")
    Update-TmuxTuiPreviewBox -Panel $Panel -Lines $previewLines
}

function Update-TmuxTuiWindowRow {
    <#
    .SYNOPSIS
        把窗口拓扑渲染到右中区(纯视图更新, 不重建视图树)。

    .DESCRIPTION
        每个窗口占两行:
            行 A: "* 0:main (zsh)"    —— * 标记活动窗口(活动窗口名 BrightWhite,
                                         非活动 Gray), 当前前台命令用暗灰
            行 B: "  └─ ~/work/hermes" —— 当前工作目录(主目录折叠成 ~), DarkGray

        宽度不足时按**显示列宽**截断(中文/宽字符安全), 窗口过多时
        从尾部丢弃(保留靠前的窗口)。

    .PARAMETER Panel
        New-TmuxTuiSessionDetailPanel 产物。

    .PARAMETER Windows
        窗口对象数组(每个含 Index/Name/Active/Panes/Command/Path/PathShort);
        为空或 $null 时渲染占位提示。
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Panel,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]]$Windows = @()
    )

    $theme = $Panel.Theme
    $width = [int]$Panel.Width
    # 行分配:
    #   5      WINDOWS & ACTIVE PROCESSES 标题
    #   6..N   窗口行(每窗口 2 行)
    #   N+1..  预览区: 标题 / 上框 / 内容(最多 8 行) / 下框
    # 预览区固定 11 行, **贴底**; 窗口区吃中间剩下的空间。
    $previewBlockHeight = 11
    if ($null -ne $Panel.PSObject.Properties['PreviewBlockHeight']) {
        $previewBlockHeight = [int]$Panel.PreviewBlockHeight
    }
    $zoneTop = 6
    $zoneBottom = [int]$Panel.Height - $previewBlockHeight - 2
    if ($zoneBottom -lt $zoneTop) { $zoneBottom = $zoneTop }

    $static = [System.Reflection.BindingFlags]'Public,Static'
    $posAbsolute = $Panel.Tgui.Types.Pos.GetMethods($static) |
        Where-Object { $_.Name -eq 'Absolute' -and $_.GetParameters().Count -eq 1 } |
        Select-Object -First 1
    $dimAbsolute = $Panel.Tgui.Types.Dim.GetMethods($static) |
        Where-Object { $_.Name -eq 'Absolute' -and $_.GetParameters().Count -eq 1 } |
        Select-Object -First 1

    # 复用的 Label 句柄(槽位化, 避免每次重建视图)
    #
    # ★ 槽位模型(2026-11-06 修复): **一个槽位 = 一行**, 而不是"一个槽位 = 一个
    #   窗口的 Name+Path 两行"。旧实现给第 i 个槽位建 Name(zoneTop+i)与
    #   Path(zoneTop+i+1)两个标签, 于是**第 i 个槽位的 Path 与第 i+1 个槽位的
    #   Name 落在同一行** —— 渲染时又按 $winRows[2k] 取窗口, 索引与行号完全
    #   对不上: 第 2 个窗口被写到第 8/9 行, 且中间几行有**空标签**压在真实
    #   内容行上(重绘时会把内容擦掉)。
    #   现在: 每个槽位只管**一行**, 窗口 k 占第 2k、2k+1 两个槽位
    #   (第 2k 行 = 窗口名, 第 2k+1 行 = 路径), 槽位索引与行号一一对应。
    if ($null -eq $Panel.WinRows -or @($Panel.WinRows).Count -eq 0) {
        $rows = [System.Collections.Generic.List[object]]::new()
        $cap = [Math]::Max(1, $zoneBottom - $zoneTop + 1)
        for ($i = 0; $i -lt $cap; $i++) {
            # 活动标记列(2 列): 只在"窗口名行"存在(偶数槽位), 路径行不需要。
            # 拆出来是为了让 `*` 能用 BrightGreen、窗口名用 BrightWhite。
            $marker = $null
            if (($i % 2) -eq 0) {
                $marker = [System.Activator]::CreateInstance($Panel.Tgui.Types.Label)
                $marker.Text = ''
                $marker.Width = $dimAbsolute.Invoke($null, @(2))
                $marker.Height = $dimAbsolute.Invoke($null, @(1))
                $marker.X = $posAbsolute.Invoke($null, @(0))
                $marker.Y = $posAbsolute.Invoke($null, @($zoneTop + $i))
                [void]$marker.SetScheme($theme.ForestPaneName)
                [void]$Panel.View.Add($marker)
            }

            $lbl = [System.Activator]::CreateInstance($Panel.Tgui.Types.Label)
            $lbl.Text = ''
            $lbl.Width = $dimAbsolute.Invoke($null, @($width))
            $lbl.Height = $dimAbsolute.Invoke($null, @(1))
            $lbl.X = $posAbsolute.Invoke($null, @(2))
            $lbl.Y = $posAbsolute.Invoke($null, @($zoneTop + $i))
            [void]$lbl.SetScheme($theme.ForestPaneName)
            [void]$Panel.View.Add($lbl)
            $rows.Add([PSCustomObject]@{ Label = $lbl; Marker = $marker }) | Out-Null
        }
        $Panel.WinRows = $rows
    }

    $winRows = @($Panel.WinRows)
    $usedSlots = 0

    foreach ($w in @($Windows)) {
        if ($null -eq $w) { continue }
        # 窗口 k 占第 2k(名称) 与 2k+1(路径) 两个**行**槽位
        $nameSlot = $usedSlots * 2
        if ($nameSlot + 1 -ge $winRows.Count) { break }

        $isActive = $false
        try { $isActive = [bool]$w.Active } catch { $isActive = $false }

        $index = ''
        try { $index = [string][int]$w.Index } catch { $index = '' }
        $winName = [string]$w.Name
        if ([string]::IsNullOrEmpty($winName)) { $winName = 'unnamed' }
        $cmd = [string]$w.Command
        if ([string]::IsNullOrEmpty($cmd)) { $cmd = '-' }

        # 行 A: "* 0:main (zsh)" / "  1:editor (nvim)"
        # ★ 活动标记 `*` 单独占一个 2 列的 Label —— 否则它和窗口名共用一个
        #   Label, 只能共享一种颜色, 而规格要求 "活动标识 * 用 BrightGreen,
        #   窗口名用 BrightWhite"。拆开才有两层。
        $marker = $winRows[$nameSlot].Marker
        if ($null -ne $marker) {
            $marker.Text = $(if ($isActive) { [string][char]0x2A } else { ' ' })   # *
            [void]$marker.SetScheme($(if ($isActive) { $theme.ForestActive } else { $theme.ForestPaneName }))
        }
        $head = "$index`:$winName ($cmd)"
        $headText = Get-SshHostListClip -Text $head -Width ([Math]::Max(1, $width - 2))
        $winRows[$nameSlot].Label.Text = $headText
        [void]$winRows[$nameSlot].Label.SetScheme($(if ($isActive) { $theme.ForestActiveName } else { $theme.ForestPaneName }))

        # 行 B: "  └─ ~/work/hermes"
        $path = [string]$w.PathShort
        if ([string]::IsNullOrEmpty($path)) { $path = [string]$w.Path }
        if ([string]::IsNullOrEmpty($path)) { $path = '-' }
        $pathText = Get-SshHostListClip -Text ("  " + [string][char]0x2514 + [string][char]0x2500 + ' ' + $path) -Width $width
        $winRows[$nameSlot + 1].Label.Text = $pathText
        [void]$winRows[$nameSlot + 1].Label.SetScheme($theme.ForestPath)

        $usedSlots++
    }

    # 没用到的槽位清空(避免残留上一个会话的窗口)
    for ($i = $usedSlots * 2; $i -lt $winRows.Count; $i++) {
        if ([string]$winRows[$i].Label.Text) { $winRows[$i].Label.Text = '' }
        if ($null -ne $winRows[$i].Marker -and [string]$winRows[$i].Marker.Text) { $winRows[$i].Marker.Text = '' }
    }

    # 空态: 没有窗口信息时给一行占位提示(而不是空白标签)
    if ($usedSlots -eq 0 -and $winRows.Count -gt 0) {
        $winRows[0].Label.Text = '(no window details available)'
        [void]$winRows[0].Label.SetScheme($theme.ForestPath)
    }
}

function Update-TmuxTuiPreviewBox {
    <#
    .SYNOPSIS
        渲染右下区的终端预览线框(纯视图更新)。

    .DESCRIPTION
        框线用 ┌ ─ ┐ │ └ ┘ (DarkGray), 内容行用 Gray。
        内容按**可用宽度**截断(中文/宽字符安全), 超出高度的行从尾部丢弃。
        没有快照时显示 "[No preview output available]"。

    .PARAMETER Panel
        New-TmuxTuiSessionDetailPanel 产物。

    .PARAMETER Lines
        预览文本行数组(纯文本, ANSI 已被数据层剥离)。
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Panel,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]]$Lines = @()
    )

    $theme = $Panel.Theme
    $width = [int]$Panel.Width
    # ★ 字符串乘法(不是 @(...) 数组乘法): 后者会被 $OFS=' ' 拼成 '─ ─ ─ …',
    #   框线宽度会翻倍并撑破面板。详见 New-TmuxTuiSessionDetailPanel 里的分隔线注释。
    $boxTop = [string][char]0x250C + (([string][char]0x2500) * ($width - 2)) + [string][char]0x2510
    $boxBottom = [string][char]0x2514 + (([string][char]0x2500) * ($width - 2)) + [string][char]0x2518
    $boxSide = [string][char]0x2502

    if ([string]$Panel.PreviewBoxTop.Text -cne $boxTop) { $Panel.PreviewBoxTop.Text = $boxTop }
    [void]$Panel.PreviewBoxTop.SetScheme($theme.ForestPreviewBox)
    if ([string]$Panel.PreviewBoxBottom.Text -cne $boxBottom) { $Panel.PreviewBoxBottom.Text = $boxBottom }
    [void]$Panel.PreviewBoxBottom.SetScheme($theme.ForestPreviewBox)

    # 内容区槽位化: 最多 8 行
    $contentTop = 7
    if ($null -ne $Panel.PSObject.Properties['PreviewContentTop']) {
        $contentTop = [int]$Panel.PreviewContentTop
    }
    if ($null -eq $Panel.PreviewRows -or @($Panel.PreviewRows).Count -eq 0) {
        $rows = [System.Collections.Generic.List[object]]::new()
        $static = [System.Reflection.BindingFlags]'Public,Static'
        $posAbsolute = $Panel.Tgui.Types.Pos.GetMethods($static) |
            Where-Object { $_.Name -eq 'Absolute' -and $_.GetParameters().Count -eq 1 } |
            Select-Object -First 1
        $dimAbsolute = $Panel.Tgui.Types.Dim.GetMethods($static) |
            Where-Object { $_.Name -eq 'Absolute' -and $_.GetParameters().Count -eq 1 } |
            Select-Object -First 1
        for ($i = 0; $i -lt 8; $i++) {
            $lbl = [System.Activator]::CreateInstance($Panel.Tgui.Types.Label)
            $lbl.Text = ''
            $lbl.Width = $dimAbsolute.Invoke($null, @($width))
            $lbl.Height = $dimAbsolute.Invoke($null, @(1))
            $lbl.X = $posAbsolute.Invoke($null, @(0))
            $lbl.Y = $posAbsolute.Invoke($null, @($contentTop + $i))
            [void]$lbl.SetScheme($theme.ForestPreview)
            [void]$Panel.View.Add($lbl)
            $rows.Add($lbl) | Out-Null
        }
        $Panel.PreviewRows = $rows
    }

    $slots = @($Panel.PreviewRows)
    # 内容区宽度: 左侧 │(1) + 1 空格 + 内容 + 1 空格 + 右侧 │(1) = 宽度
    $inner = $width - 4
    if ($inner -lt 4) { $inner = 4 }

    $texts = @($Lines | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_ })
    if ($texts.Count -eq 0) { $texts = @('[No preview output available]') }

    for ($i = 0; $i -lt $slots.Count; $i++) {
        $text = ''
        if ($i -lt $texts.Count) {
            $text = Get-SshHostListClip -Text $texts[$i] -Width $inner
            # 补齐到内宽(短行也要把右竖线推到同一列, 框才是闭合的)
            $pad = $inner - (Get-TguiTextWidth -Text $text)
            if ($pad -lt 0) { $pad = 0 }
            $text = ' ' + $text + (' ' * $pad)
        }
        else {
            $text = (' ' * ($inner + 1))
        }
        $full = $boxSide + $text + $boxSide
        if ([string]$slots[$i].Text -cne $full) { $slots[$i].Text = $full }
        [void]$slots[$i].SetScheme($theme.ForestPreview)
    }
}
