# Invoke-MenuMachine.ps1 - 通用菜单交互状态机
# 统一键盘事件分发: 解决 Show-HostSelector 中碎片化的 if/else 链
# 状态: Idle / Selecting / Filtering / Inputting
# 委托: New-AnsiLayout(布局) + Write-MenuItem(项渲染) + New-StatusBadge(状态)
# 委托: Get-KeyboardFilter(过滤逻辑, P1-2 抽出)

. "$PSScriptRoot\New-AnsiLayout.ps1"
. "$PSScriptRoot\Write-MenuItem.ps1"
. "$PSScriptRoot\New-StatusBadge.ps1"

function New-MenuContext {
    <#
    .SYNOPSIS
        构造菜单状态机上下文(状态 + 可见项 + 选中索引 + 过滤字符串)

    .DESCRIPTION
        持有所有可变状态, 作为引用传递给状态机各事件处理函数。
        State 字段: Idle(未交互) / Selecting(浏览) / Filtering(输入过滤) / Inputting(文本输入)

    .PARAMETER AllItems
        全部菜单项数组(New-MenuItem 构造)

    .PARAMETER ExitItem
        EXIT 项(可为 $null), 用于 ESC 退出场景

    .PARAMETER InitialFilter
        初始过滤字符串(默认空)

    .PARAMETER AllowFilter
        是否允许键盘过滤(默认 $true)

    .EXAMPLE
        $ctx = New-MenuContext -AllItems $items -ExitItem $exit
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'New-MenuContext 是状态机纯构造函数,无外部副作用')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseBOMForUnicodeEncodedFile', '')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [array]$AllItems,

        [Parameter(Mandatory = $false)]
        [PSCustomObject]$ExitItem,

        [Parameter(Mandatory = $false)]
        [string]$InitialFilter = "",

        [Parameter(Mandatory = $false)]
        [bool]$AllowFilter = $true
    )
    return [PSCustomObject]@{
        AllItems    = @($AllItems)
        ExitItem    = $ExitItem
        Filter      = $InitialFilter
        SelectedIdx = 0
        State       = 'Idle'
        AllowFilter = $AllowFilter
    }
}


function Get-VisibleMenuItems {
    <#
    .SYNOPSIS
        根据当前 Filter 计算可见菜单项(应用键盘过滤)

    .PARAMETER Context
        New-MenuContext 返回的上下文

    .OUTPUTS
        当前应渲染的菜单项数组(已包含 EXIT)
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Context
    )
    $items = $Context.AllItems
    $filter = $Context.Filter

    if ([string]::IsNullOrEmpty($filter)) {
        return ,$items
    }
    $f = $filter.ToLowerInvariant()
    $matched = @($items | Where-Object {
        $_.Label -and ($_.Label.ToLowerInvariant().Contains($f)) -and -not $_.Disabled
    })
    # 始终保留 EXIT 项
    if ($Context.ExitItem) {
        $matched += $Context.ExitItem
    }
    if ($matched.Count -eq 0 -and $Context.ExitItem) {
        return ,@($Context.ExitItem)
    }
    return ,$matched
}

function Send-MenuKey {
    <#
    .SYNOPSIS
        向菜单状态机发送一个键盘事件, 返回更新后的上下文

    .DESCRIPTION
        单一键盘事件分发入口。返回:
          - 更新后的 Context(若状态改变)
          - $null(若用户按 Esc/Q 退出)
          - [PSCustomObject]@{ Action = 'Select'; Item = <selected> }(若用户按 Enter 确认)

        不直接操作控制台, 渲染由调用方在拿到新 Context 后执行。

    .PARAMETER Context
        菜单上下文

    .PARAMETER Key
        原始 ReadKey 返回的 KeyInfo 对象
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Context,

        [Parameter(Mandatory = $true)]
        [System.ConsoleKeyInfo]$Key
    )

    $vK = $Key.VirtualKeyCode
    $char = $Key.Character

    # 退出: Esc(27) 或 Q/q
    if ($vK -eq 27 -or $char -eq 'q' -or $char -eq 'Q') {
        return $null
    }

    $visible = Get-VisibleMenuItems -Context $Context
    $count = $visible.Count
    if ($count -eq 0) { return $Context }

    # 上/下导航
    if ($vK -eq 38) {  # Up
        $Context.SelectedIdx = ($Context.SelectedIdx - 1 + $count) % $count
        $Context.State = 'Selecting'
        return $Context
    }
    if ($vK -eq 40) {  # Down
        $Context.SelectedIdx = ($Context.SelectedIdx + 1) % $count
        $Context.State = 'Selecting'
        return $Context
    }

    # Enter: 确认
    if ($vK -eq 13) {
        $sel = $visible[$Context.SelectedIdx]
        # EXIT 项判断: ExitItem 存在且 Label 匹配
        if ($Context.ExitItem -and $sel.Label -eq $Context.ExitItem.Label) {
            return $null
        }
        return [PSCustomObject]@{ Action = 'Select'; Item = $sel }
    }

    # 过滤控制
    if (-not $Context.AllowFilter) { return $Context }

    # Backspace: 删除末字符
    if ($vK -eq 8) {
        if ($Context.Filter.Length -gt 0) {
            $Context.Filter = $Context.Filter.Substring(0, $Context.Filter.Length - 1)
            $Context.State = 'Filtering'
        }
        return $Context
    }
    # Ctrl+U: 清空过滤
    if ($vK -eq 17) {
        $Context.Filter = ""
        $Context.State = 'Filtering'
        return $Context
    }
    # 可打印字符: 追加到过滤
    if ($char -and $char -match '^[a-zA-Z0-9\.\-_]$') {
        $Context.Filter += $char
        $Context.State = 'Filtering'
        # 过滤变化时重置选中索引到 0
        $visible2 = Get-VisibleMenuItems -Context $Context
        $Context.SelectedIdx = 0
        return $Context
    }

    return $Context
}

function Invoke-MenuMachine {
    <#
    .SYNOPSIS
        菜单状态机主循环: 渲染上下文 + 读取键盘 + 分发 + 循环, 直至退出或确认

    .DESCRIPTION
        整合 New-MenuContext / Send-MenuKey / 渲染循环。
        调用方只需提供 Items + 渲染器(Write-MenuItem 风格), 状态机负责一切交互。

    .PARAMETER Context
        New-MenuContext 构造的初始上下文

    .PARAMETER Layout
        New-AnsiLayout 返回的布局对象(已设置好 Header/Footer, Main 留空)

    .PARAMETER Colors
        颜色覆盖表, 传递给 Write-MenuItem

    .PARAMETER ExitLabel
        EXIT 项文字(用于预构 selected/unselected 行)

    .PARAMETER OnRender
        自定义渲染回调(可选): 接收 ($Layout, $VisibleItems, $SelectedIdx, $Filter) 四参数,
        用于自定义 Main 区域内容(默认走标准菜单渲染)

    .OUTPUTS
        选中的菜单项 PSCustomObject, 或 $null(用户退出)
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Context,

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Layout,

        [Parameter(Mandatory = $false)]
        [hashtable]$Colors,

        [Parameter(Mandatory = $false)]
        [string]$ExitLabel = "EXIT",

        [Parameter(Mandatory = $false)]
        [scriptblock]$OnRender
    )

    if (-not $Colors) { $Colors = @{} }
    $primary = if ($Colors.Primary) { $Colors.Primary } else { Get-CachedConfig -Section 'Colors' -Key 'FreshGreen' -Default "`e[38;2;137;209;133m" }
    $accent  = if ($Colors.Accent)  { $Colors.Accent  } else { Get-CachedConfig -Section 'Colors' -Key 'SageGreen'  -Default "`e[38;2;159;177;159m" }
    $muted   = if ($Colors.Muted)   { $Colors.Muted   } else { Get-CachedConfig -Section 'Colors' -Key 'MidGray'    -Default "`e[38;2;100;100;100m" }
    $rst     = if ($Colors.Rst)     { $Colors.Rst     } else { Get-CachedConfig -Section 'Colors' -Key 'Rst' -Default "`e[0m" }
    $fullColors = @{ Primary = $primary; Accent = $accent; Muted = $muted; Rst = $rst }

    # 预构 EXIT 行模板
    $exitKey = ($Context.AllItems.Count + 1).ToString().PadLeft(2, '0')
    $exitSelected   = "  ${primary}|${rst}  ${rst}>${rst} ${accent}[${exitKey}]${rst} ${accent}${ExitLabel}${rst}"
    $exitUnselected = "  ${primary}|${rst}  ${muted} ${rst} ${accent}[${exitKey}]${rst} ${muted}${ExitLabel}${rst}"

    # 默认渲染器: 写过滤提示行 + 列表项
    $defaultRender = {
        param($Layout, $VisibleItems, $SelectedIdx, $Filter, $Colors, $ExitLabel, $ExitSelected, $ExitUnselected, $ExitItem)
        $primary = $Colors.Primary
        $accent  = $Colors.Accent
        $muted   = $Colors.Muted
        $rst     = $Colors.Rst

        $Layout.Main.Clear()
        if ($Filter) {
            $Layout.Main.Add("  ${primary}|${rst}  ${accent}搜索: ${primary}${Filter}_${rst}") | Out-Null
        } else {
            $Layout.Main.Add("  ${primary}|${rst}  ${muted}输入字符即时过滤${rst}") | Out-Null
        }
        $Layout.Main.Add("  ${primary}|${rst}") | Out-Null

        for ($i = 0; $i -lt $VisibleItems.Count; $i++) {
            $item = $VisibleItems[$i]
            $isSel = ($i -eq $SelectedIdx)
            if ($ExitItem -and $item.Label -eq $ExitItem.Label) {
                $Layout.Main.Add((if ($isSel) { $ExitSelected } else { $ExitUnselected })) | Out-Null
            } else {
                $Layout.Main.Add((Write-MenuItem -Item $item -Index $i -IsSelected $isSel -Colors $Colors)) | Out-Null
            }
        }
    }
    $renderer = if ($OnRender) { $OnRender } else { $defaultRender }

    # 主循环
    while ($true) {
        $visible = Get-VisibleMenuItems -Context $Context
        if ($Context.SelectedIdx -ge $visible.Count) { $Context.SelectedIdx = [Math]::Max(0, $visible.Count - 1) }

        # 渲染
        & $renderer $Layout $visible $Context.SelectedIdx $Context.Filter $fullColors $ExitLabel $exitSelected $exitUnselected $Context.ExitItem
        Show-AnsiLayout -Layout $Layout

        # 读取键盘
        try {
            $key = $Host.UI.RawUI.ReadKey("NoEcho, IncludeKeyDown")
        } catch {
            [Console]::Clear()
            return $null
        }

        $result = Send-MenuKey -Context $Context -Key $key

        if ($null -eq $result) {
            [Console]::Clear()
            return $null
        }
        if ($result -is [PSCustomObject] -and $result.Action -eq 'Select') {
            [Console]::Clear()
            return $result.Item
        }
        # 否则 result 即为更新后的 Context, 继续循环
        $Context = $result
    }
}
