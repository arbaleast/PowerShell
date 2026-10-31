# New-SshHostDetailPanel.ps1 - 仪表盘右侧主机详情面板(多卡片 + 就地更新)
#
# 背景 (2026-10-31 sss 仪表盘重构):
#   右侧详情必须把"本地立刻知道的信息"和"需要远端查询的信息"分开:
#     - Connection: Host/地址/User 来自 ~/.ssh/config, **选中即立刻更新**;
#       连接状态来自远端探测, 异步回填。
#     - Activity: 最后活跃/最近连接/7 日直方图来自本地活动历史(真实数据),
#       无记录时明确显示"无记录", 绝不伪造。
#     - Tags: 标签/分组来自主机档案元数据。
#     - Infrastructure: 云服务商 / Region —— **仅在数据存在时显示卡片**。
#   因此本文件的函数分成三类:
#     New-SshHostDetailPanel        组装(纯视图, 无头可测)
#     Set-SshHostDetailBasic        本地数据落位(同步, 键盘回调里安全)
#     Set-SshHostDetailRemote       远端数据落位(异步轮询回调里调用)
#     Set-SshHostDetailState        加载中/失败/无数据 三态
#
# ★ 卡片用 FrameView(Goal 明确建议): TG 2.4.10 的 FrameView 有 Title + 边框,
#   边框/标题取自身 Scheme, 内容子视图各自取自己的 Scheme —— 于是"暗灰细边框 +
#   亮字内容 + 紫色标题"可以在同一张卡片里共存。
# ★ 卡片高度按可用高度动态分配: 面板矮时按 Infrastructure -> Tags -> Activity
#   的次序整卡收起(Connection 永远保留, 它是用户最需要的信息), 不出现半截卡片。
#
# 契约: 不读文件/不发网络; 所有文本都来自调用方传入的行模型/探测结果。

function Get-SshHostDetailCardPlan {
    <#
    .SYNOPSIS
        按面板可用高度决定显示哪几张卡片、各多高(纯计算, 可单测)。

    .DESCRIPTION
        卡片最小高度 = 边框 2 行 + 内容行数; 面板不够时按
        Infrastructure -> Tags -> Activity 的优先级整卡收起,
        Connection 保底(最小 4 行: 边框 + Host/地址两行)。
        剩余高度补给 Connection/Activity(它们的信息量最大)。

    .PARAMETER Height
        右侧面板可用高度(行)。

    .PARAMETER HasInfrastructure
        是否有云服务商/Region 数据 —— 没有就**根本不显示**该卡片(不画空卡)。

    .OUTPUTS
        [PSCustomObject] Connection/Activity/Tags/Infrastructure 的卡片高度
                        (0 = 不显示), 以及 Total。

    .EXAMPLE
        $plan = Get-SshHostDetailCardPlan -Height 31 -HasInfrastructure $true
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [int]$Height,

        [Parameter(Mandatory = $false)]
        [bool]$HasInfrastructure = $false
    )

    # 内容行数(不含边框): Connection 5 / Activity 3 / Tags 2 / Infrastructure 2
    # Connection 的 5 行 = Host / Address / Port / User / Status(Goal 二-3 逐项对齐)
    $connMin = 5 + 2
    $actMin = 3 + 2
    $tagsMin = 2 + 2
    $infraMin = 2 + 2
    # 每张卡片之间留 1 行空隙
    $gap = 1

    $conn = $connMin
    $act = 0
    $tags = 0
    $infra = 0
    $needed = $conn
    if ($Height -ge $needed + $gap + $actMin) { $act = $actMin; $needed += $gap + $actMin }
    if ($Height -ge $needed + $gap + $tagsMin) { $tags = $tagsMin; $needed += $gap + $tagsMin }
    if ($HasInfrastructure -and $Height -ge $needed + $gap + $infraMin) { $infra = $infraMin; $needed += $gap + $infraMin }

    # 剩余高度: 先给 Connection(最多 +2), 再给 Activity(最多 +1), 再给 Tags
    $spare = $Height - $needed
    if ($spare -gt 0) { $give = [Math]::Min(2, $spare); $conn += $give; $spare -= $give }
    if ($spare -gt 0 -and $act -gt 0) { $give = [Math]::Min(1, $spare); $act += $give; $spare -= $give }
    if ($spare -gt 0 -and $tags -gt 0) { $tags += $spare; $spare = 0 }

    return [PSCustomObject]@{
        Connection     = $conn
        Activity       = $act
        Tags           = $tags
        Infrastructure = $infra
        Total          = $conn + $act + $tags + $infra
    }
}

function New-SshHostDetailPanel {
    <#
    .SYNOPSIS
        组装右侧详情面板(垂直排列的 FrameView 卡片 + 键值 Label)。

    .DESCRIPTION
        返回对象里带全部**值 Label** 的句柄, 供 Set-SshHostDetailBasic /
        Set-SshHostDetailRemote 就地更新文本(改 Label.Text 只重画该标签,
        不重建视图)。

    .PARAMETER Width
        面板宽度(列)。

    .PARAMETER Height
        面板高度(行)。

    .PARAMETER HasInfrastructure
        是否显示 Infrastructure 卡片。

    .PARAMETER Theme
        Get-SshHostDashboardTheme 产物。

    .PARAMETER Tgui
        Get-TguiContext 产物。

    .OUTPUTS
        [PSCustomObject] View/Plan/Labels(哈希表)/Cards

    .EXAMPLE
        $panel = New-SshHostDetailPanel -Width 56 -Height 31 -HasInfrastructure $true -Theme $theme -Tgui $tg
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
        [bool]$HasInfrastructure = $false,

        [Parameter(Mandatory = $true)]
        [object]$Theme,

        [Parameter(Mandatory = $true)]
        [object]$Tgui
    )

    if ($PSCmdlet.ShouldProcess('SSH 主机详情面板', 'Construct')) { } else { return $null }

    $static = [System.Reflection.BindingFlags]'Public,Static'
    $posAbsolute = $Tgui.Types.Pos.GetMethods($static) |
        Where-Object { $_.Name -eq 'Absolute' -and $_.GetParameters().Count -eq 1 } |
        Select-Object -First 1
    $dimAbsolute = $Tgui.Types.Dim.GetMethods($static) |
        Where-Object { $_.Name -eq 'Absolute' -and $_.GetParameters().Count -eq 1 } |
        Select-Object -First 1
    $labelType = $Tgui.Types.Label
    $frameType = $Tgui.Types.FrameView
    $viewType = $Tgui.Types.View

    $container = [System.Activator]::CreateInstance($viewType)
    $container.X = $posAbsolute.Invoke($null, @(0))
    $container.Y = $posAbsolute.Invoke($null, @(0))
    $container.Width = $dimAbsolute.Invoke($null, @($Width))
    $container.Height = $dimAbsolute.Invoke($null, @($Height))
    [void]$container.SetScheme($Theme.Text)

    $plan = Get-SshHostDetailCardPlan -Height $Height -HasInfrastructure $HasInfrastructure
    $cardWidth = [Math]::Max(20, $Width)

    # 卡片正文里"键"列宽 9 + 1 空格, 值列吃满剩余(减去左右边框各 1 与内缩 1)
    $keyX = 2
    $keyWidth = 9
    $valueX = $keyX + $keyWidth + 1
    $valueWidth = [Math]::Max(6, $cardWidth - $valueX - 2)

    $labels = @{}
    $cards = @{}
    # 已应用方案登记表: SetScheme 不是幂等 no-op(TG 会无条件把视图标脏),
    # 而"上一台主机"与"这一台主机"的 Status 方案往往相同 —— 等值跳过能
    # 显著缩小重绘脏区(见 p38 实测)。键 = 卡片键名, 值 = 上次应用的 Scheme。
    $appliedSchemes = @{}
    # 原始值登记表: 用于"原值没变就完全不碰视图"(含跳过截断计算)
    $rawValues = @{}
    $y = 0

    function New-DetailLabel {
        # 纯视图工厂(只 new 一个 Label), 不改变系统状态
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
        param([int]$X, [int]$Y, [int]$W, [string]$Text, [object]$Scheme)
        $lbl = [System.Activator]::CreateInstance($labelType)
        $lbl.Text = $Text
        $lbl.X = $posAbsolute.Invoke($null, @($X))
        $lbl.Y = $posAbsolute.Invoke($null, @($Y))
        $lbl.Width = $dimAbsolute.Invoke($null, @([Math]::Max(1, $W)))
        $lbl.Height = $dimAbsolute.Invoke($null, @(1))
        [void]$lbl.SetScheme($Scheme)
        return $lbl
    }

    function New-DetailCard {
        # 纯视图工厂(只 new 一个 FrameView), 不改变系统状态
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
        param([string]$Title, [int]$Height, [string[]]$Keys, [int]$Y)
        $card = [System.Activator]::CreateInstance($frameType)
        $card.X = $posAbsolute.Invoke($null, @(0))
        $card.Y = $posAbsolute.Invoke($null, @($Y))
        $card.Width = $dimAbsolute.Invoke($null, @($cardWidth))
        $card.Height = $dimAbsolute.Invoke($null, @($Height))
        try { $card.Title = " $Title " } catch { Write-Verbose "[New-SshHostDetailPanel] 卡片标题设置失败: $($_.Exception.Message)" }
        [void]$card.SetScheme($Theme.CardBorder)
        # 内容行从边框内侧第 1 行开始
        for ($i = 0; $i -lt $Keys.Count; $i++) {
            if ($i + 2 -gt $Height) { break }
            $k = New-DetailLabel -X $keyX -Y (1 + $i) -W $keyWidth -Text $Keys[$i] -Scheme $Theme.Dim
            $v = New-DetailLabel -X $valueX -Y (1 + $i) -W $valueWidth -Text '' -Scheme $Theme.Card
            [void]$card.Add($k)
            [void]$card.Add($v)
            $labels[$Keys[$i]] = $v
        }
        return $card
    }

    # FrameView 的 Y 由外层循环逐卡累加(嵌套函数里改 $y 不会冒泡, 故用参数传入)
    $cardKeys = @{
        Connection = @('Host', 'Address', 'Port', 'User', 'Status')
        Activity   = @('Last', 'Recent', 'History')
        Tags       = @('Tags', 'Group')
        Infrastructure = @('Provider', 'Region')
    }
    $cardTitles = @{
        Connection = 'Connection'; Activity = 'Activity'; Tags = 'Tags'; Infrastructure = 'Infrastructure'
    }

    foreach ($name in @('Connection', 'Activity', 'Tags', 'Infrastructure')) {
        $h = $plan.$name
        if ($h -le 0) { continue }
        $card = New-DetailCard -Title $cardTitles[$name] -Height $h -Keys $cardKeys[$name] -Y $y
        # 键列方案统一为暗灰(在 New-DetailCard 里已设置), 卡片边框同色
        [void]$container.Add($card)
        $cards[$name] = $card
        $y += $h + 1
    }

    $panel = [PSCustomObject]@{
        View   = $container
        Cards  = $cards
        Labels = $labels
        AppliedSchemes = $appliedSchemes
        RawValues = $rawValues
        Plan   = $plan
        Width  = $Width
        Height = $Height
        Theme  = $Theme
        Tgui   = $Tgui
    }
    return $panel
}

function Set-SshHostDetailLabelText {
    <#
    .SYNOPSIS
        就地改一个详情值 Label 的文本 —— **文本没变就不写**。

    .DESCRIPTION
        TG 的 Label 在 Text 被重新赋值时无条件把自己标脏; 而"切换到下一台
        主机"时, 大量字段(Address/Port/User/Tags…)的文本与上一台**完全相同**。
        等值跳过能把重绘脏区从"整张详情面板"缩回"真正变化的字段"。

    .PARAMETER Label
        Terminal.Gui Label 实例。

    .PARAMETER Text
        新文本。
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$Label,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$Text = ''
    )

    if ($null -eq $Label) { return }
    if ([string]$Label.Text -ceq $Text) { return }
    $Label.Text = $Text
}

function Set-SshHostDetailLabelScheme {
    <#
    .SYNOPSIS
        就地改一个详情值 Label 的配色 —— **方案没变就不写**。

    .DESCRIPTION
        TG 2.4.10 的 View.SetScheme 会无条件把视图标脏(不是幂等 no-op)。
        详情面板里 Status 的方案在同一状态下(Unknown -> Unknown)是同一个实例,
        等值跳过即可避免"每按一次方向键就重画整张详情面板"。

    .PARAMETER Panel
        New-SshHostDetailPanel 产物(用它的 AppliedSchemes 做等值登记)。

    .PARAMETER Key
        卡片键名(如 'Status')。

    .PARAMETER Scheme
        目标 Scheme 实例。
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Panel,

        [Parameter(Mandatory = $true)]
        [string]$Key,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$Scheme
    )

    $label = $Panel.Labels[$Key]
    if ($null -eq $label -or $null -eq $Scheme) { return }
    if ($Panel.AppliedSchemes.ContainsKey($Key) -and $Panel.AppliedSchemes[$Key] -eq $Scheme) { return }
    [void]$label.SetScheme($Scheme)
    $Panel.AppliedSchemes[$Key] = $Scheme
}

function Set-SshHostDetailBasic {
    <#
    .SYNOPSIS
        用**本地已知**数据刷新详情卡片(选中主机后立刻调用, 不做任何网络操作)。

    .PARAMETER Panel
        New-SshHostDetailPanel 产物。

    .PARAMETER Row
        行视图模型(Get-SshHostDashboardRow 产物, 字段见该函数)。

    .PARAMETER Activity
        该主机的本地活动记录(Get-SshHostActivity 产物); $null = 无记录。
    #>
    # 纯内存视图刷新(不改变系统状态) —— 抑制 PSSA 的 ShouldProcess 规则
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Panel,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$Row,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$Activity
    )

    $theme = $Panel.Theme
    $valueWidth = [Math]::Max(6, $Panel.Width - 14)

    function Set-DetailValue {
        param([string]$Key, [string]$Text)
        $lbl = $Panel.Labels[$Key]
        if ($null -eq $lbl) { return }
        # ★ 原值未变 -> 连截断都不用算: 详情面板有 12 个字段, 切换主机时
        #   大部分字段的**原值**与上一台完全相同。截断要逐字符测宽,
        #   是按键路径上第二大的开销(p39 实测 2.45ms/次)。
        if ($Panel.RawValues.ContainsKey($Key) -and $Panel.RawValues[$Key] -ceq $Text) { return }
        $Panel.RawValues[$Key] = $Text
        Set-SshHostDetailLabelText -Label $lbl -Text (Get-SshHostListClip -Text $Text -Width $valueWidth)
    }

    if ($null -eq $Row) {
        # 空列表(分类/过滤后无主机): 值列明确写"无", 不残留上一台主机的信息
        foreach ($k in @('Host', 'Address', 'Port', 'User', 'Status', 'Last', 'Recent', 'History', 'Tags', 'Group', 'Provider', 'Region')) {
            Set-DetailValue -Key $k -Text ''
        }
        $status = $Panel.Labels['Status']
        if ($status) {
            Set-SshHostDetailLabelText -Label $status -Text '—'
            Set-SshHostDetailLabelScheme -Panel $Panel -Key 'Status' -Scheme $theme.Dim
        }
        return
    }

    Set-DetailValue -Key 'Host' -Text ([string]$Row.Name)
    # Address = IP / Hostname(权威值来自 ssh config 的 HostName 指令);
    # Port 单独一行(Goal 二-3 的 Connection 卡片逐项对齐), 不再拼进地址里。
    Set-DetailValue -Key 'Address' -Text ([string]$Row.HostName)
    $portText = ''
    if ($Row.Port) { $portText = [string]([int]$Row.Port) }
    Set-DetailValue -Key 'Port' -Text $portText
    Set-DetailValue -Key 'User' -Text $(if ($Row.User) { [string]$Row.User } else { '(默认)' })

    # 连接状态: 探测结果未回填前显示"未知"/"探测中", 绝不提前显示"在线"
    $statusLabel = $Panel.Labels['Status']
    if ($statusLabel) {
        $statusText = '{0} {1}' -f [string]$Row.StatusGlyph, [string]$Row.StatusText
        Set-SshHostDetailLabelText -Label $statusLabel -Text (Get-SshHostListClip -Text $statusText -Width $valueWidth)
        $scheme = switch ($Row.StatusRole) {
            'Online' { $theme.Online }
            'Offline' { $theme.Offline }
            default { $theme.Unknown }
        }
        Set-SshHostDetailLabelScheme -Panel $Panel -Key 'Status' -Scheme $scheme
    }

    # ---- Activity: 只展示真实记录 ----
    $lastText = ''
    $recentText = ''
    $historyText = ''
    if ($null -ne $Activity) {
        $lastSeen = $null
        $prop = $Activity.PSObject.Properties['LastSeen']
        if ($null -ne $prop) { $lastSeen = $prop.Value }
        if ($null -ne $lastSeen) {
            $lastText = '{0} ({1})' -f ([datetime]$lastSeen).ToString('MM-dd HH:mm'), (Get-SshHostRelativeTime -Time ([datetime]$lastSeen))
        }
        $recent = @()
        $rProp = $Activity.PSObject.Properties['Recent']
        if ($null -ne $rProp -and $rProp.Value) { $recent = @($rProp.Value) }
        if ($recent.Count -gt 0) {
            $tail = @($recent | Select-Object -Last 3)
            $recentText = (@($tail | ForEach-Object { ([datetime]$_).ToString('MM-dd HH:mm') })) -join ' · '
        }
        $buckets = @()
        $bProp = $Activity.PSObject.Properties['DayBuckets']
        if ($null -ne $bProp -and $bProp.Value) { $buckets = @($bProp.Value) }
        if ($buckets.Count -gt 0) {
            $historyText = Format-SshHostActivityHistogram -Buckets $buckets
        }
    }
    if (-not $lastText) { $lastText = '无记录' }
    if (-not $recentText) { $recentText = '—' }
    if (-not $historyText) { $historyText = '—' }
    Set-DetailValue -Key 'Last' -Text $lastText
    Set-DetailValue -Key 'Recent' -Text $recentText
    Set-DetailValue -Key 'History' -Text $historyText

    # ---- Tags / Infrastructure ----
    $tagText = ''
    if ($Row.Tags -and @($Row.Tags).Count -gt 0) {
        $tagText = (@($Row.Tags) | ForEach-Object { '#' + $_ }) -join ' '
    }
    Set-DetailValue -Key 'Tags' -Text $(if ($tagText) { $tagText } else { '—' })
    Set-DetailValue -Key 'Group' -Text $(if ($Row.Group) { [string]$Row.Group } else { '—' })
    Set-DetailValue -Key 'Provider' -Text $(if ($Row.Provider) { [string]$Row.Provider } else { '—' })
    Set-DetailValue -Key 'Region' -Text $(if ($Row.Region) { [string]$Row.Region } else { '—' })
}

function Format-SshHostActivityHistogram {
    <#
    .SYNOPSIS
        把 7 日连接次数变成一行等宽直方图(真实活动的可视化, 不伪造数据)。

    .DESCRIPTION
        只用 5 档方块字符(空格 / ▁ / ▃ / ▅ / █), 全部是 East Asian Width =
        Narrow 的 Block Elements, 等宽字体下宽度稳定为一列; 不做"没有数据也
        画几个柱子"的填充 —— 全 0 时返回 '—'。

    .PARAMETER Buckets
        7 个每日次数(旧 -> 新)。

    .OUTPUTS
        [string] 直方图文本; 全 0 返回 '—'。

    .EXAMPLE
        Format-SshHostActivityHistogram -Buckets @(0,1,3,0,5,2,0)   # => ' ▁▃ ▅▃ ' 形态
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [int[]]$Buckets = @()
    )

    if (-not $Buckets -or $Buckets.Count -eq 0) { return [string][char]0x2014 }
    $max = ($Buckets | Measure-Object -Maximum).Maximum
    if ($max -le 0) { return [string][char]0x2014 }

    $levels = @(' ', [string][char]0x2581, [string][char]0x2583, [string][char]0x2585, [string][char]0x2588)
    $sb = [System.Text.StringBuilder]::new()
    foreach ($b in $Buckets) {
        $idx = 0
        if ($b -gt 0) {
            $idx = [int][Math]::Ceiling(($b / $max) * 4)
            if ($idx -lt 1) { $idx = 1 }
            if ($idx -gt 4) { $idx = 4 }
        }
        [void]$sb.Append($levels[$idx])
    }
    return $sb.ToString()
}

function Set-SshHostDetailRemote {
    <#
    .SYNOPSIS
        把异步探测结果落到详情面板(Connection 状态 + 远端信息)。

    .DESCRIPTION
        只更新状态与远端字段, 不动本地字段(避免旧结果覆盖新选中主机的基础信息)。
        **调用方必须先做请求标识配对**(旧请求的结果不许进这里)。

    .PARAMETER Panel
        New-SshHostDetailPanel 产物。

    .PARAMETER Detail
        Get-SshHostDetail 产物。
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Panel,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$Detail
    )

    if ($null -eq $Detail) { return }
    $theme = $Panel.Theme
    $valueWidth = [Math]::Max(6, $Panel.Width - 14)

    $statusLabel = $Panel.Labels['Status']
    if ($statusLabel) {
        $statusText = [string]$Detail.StatusText
        if ([string]$Detail.Status -eq 'Online') {
            if ($Detail.ElapsedMs) { $statusText = '{0} · {1}ms' -f $statusText, $Detail.ElapsedMs }
        }
        elseif ([string]$Detail.Status -eq 'Offline') {
            if ([string]$Detail.ErrorCode) { $statusText = '{0} · {1}' -f $statusText, [string]$Detail.ErrorCode }
        }
        $statusLabel.Text = Get-SshHostListClip -Text $statusText -Width $valueWidth
        $scheme = switch ([string]$Detail.Status) {
            'Online' { $theme.Online }
            'Offline' { $theme.Offline }
            default { $theme.Unknown }
        }
        Set-SshHostDetailLabelScheme -Panel $Panel -Key 'Status' -Scheme $scheme
    }

    # 远端补充信息写进 Activity 的 Last 行下方? 不 —— 保持卡片语义:
    # 远端 hostname / uptime / load / tmux 会话数 属于 Connection 之外的实时信息,
    # 这里仅在地址行可用时补一个"远端主机名", 其余(load/tmux)进 Status 卡片无从展示
    # 就不再塞 —— 宁可不显示, 也不把数据塞进语义不符的位置。
    $addressLabel = $Panel.Labels['Address']
    if ($addressLabel -and [string]$Detail.RemoteHostname) {
        # 地址行保持原样(它是配置的权威值), 远端 hostname 只在不一致时补注
        $current = [string]$addressLabel.Text
        if ($current -and $current.IndexOf([string]$Detail.RemoteHostname) -lt 0) {
            $addressLabel.Text = Get-SshHostListClip -Text ("{0} → {1}" -f $current, [string]$Detail.RemoteHostname) -Width $valueWidth
        }
    }
}

function Set-SshHostDetailState {
    <#
    .SYNOPSIS
        在状态行显示"探测中 / 无数据 / 失败"三态。

    .PARAMETER Panel
        New-SshHostDetailPanel 产物。

    .PARAMETER State
        Loading | Error | Unknown

    .PARAMETER Text
        附加说明(如错误码/原因摘要)。
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Panel,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Loading', 'Error', 'Unknown')]
        [string]$State,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$Text = ''
    )

    $theme = $Panel.Theme
    $valueWidth = [Math]::Max(6, $Panel.Width - 14)
    $statusLabel = $Panel.Labels['Status']
    if ($null -eq $statusLabel) { return }

    switch ($State) {
        'Loading' {
            Set-SshHostDetailLabelText -Label $statusLabel -Text (Get-SshHostListClip -Text ('● 探测中…') -Width $valueWidth)
            Set-SshHostDetailLabelScheme -Panel $Panel -Key 'Status' -Scheme $theme.Dim
        }
        'Error' {
            $msg = if ($Text) { $Text } else { '未知错误' }
            Set-SshHostDetailLabelText -Label $statusLabel -Text (Get-SshHostListClip -Text ('✗ {0}' -f $msg) -Width $valueWidth)
            Set-SshHostDetailLabelScheme -Panel $Panel -Key 'Status' -Scheme $theme.Offline
        }
        default {
            Set-SshHostDetailLabelText -Label $statusLabel -Text (Get-SshHostListClip -Text ('● 未知') -Width $valueWidth)
            Set-SshHostDetailLabelScheme -Panel $Panel -Key 'Status' -Scheme $theme.Unknown
        }
    }
}
