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
        AllItems        = @($AllItems)
        ExitItem        = $ExitItem
        Filter          = $InitialFilter
        SelectedIdx     = 0
        State           = 'Idle'
        AllowFilter     = $AllowFilter
        # CSI 重组在主循环 ReadKey 之后同步吞字节 2/3, 不需要 defer 到下一轮,
        # 故无需在 Context 上挂 PendingEscape 状态字段。
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

function ConvertTo-CsiArrowKey {
    <#
    .SYNOPSIS
        吞掉多字节 CSI 序列, 合成一个 UpArrow/DownArrow/LeftArrow/RightArrow 的 ConsoleKeyInfo。

    .DESCRIPTION
        解决 Windows Terminal + PowerShell 5.1 下方向键被分成 3 次 ReadKey 读取的问题:
        字节 1 = ESC (vK=27, char=0x1B, key=Escape)
        字节 2 = '[' (vK=0,  char='[',   key=NoName)
        字节 3 = 'A'/'B'/'C'/'D' (上/下/右/左)
        单凭字节 1 无法判断"真 ESC 按键"还是"方向键前缀", 需等待字节 2:
          - 字节 2 == '[' → 吞, 读字节 3 判定方向, 合成 UpArrow/DownArrow/LeftArrow/RightArrow
          - 字节 2 != '[' → 保留为字节 1 (此函数不消费字节 2, 由调用方下一轮 ReadKey 重新读到)

        ReadKey 来源可被 -NextKeyProvider 覆盖, 方便 Pester 注入(真实主机调用无需传参)。

    .PARAMETER FirstByte
        第一次 ReadKey 返回的 ConsoleKeyInfo, 需满足 vK=27, char=0x1B, key=Escape 才是 ESC 前缀。

    .PARAMETER NextKeyProvider
        读取下一字节的 scriptblock, 默认 = { $Host.UI.RawUI.ReadKey("NoEcho, IncludeKeyDown") }。
        返回值需为 ConsoleKeyInfo。
        注: PS 5.1 下 ConsoleKeyInfo 跨 & $mod { } 边界后 Character 字段会被 .NET 丢空,
        测试场景下 provider 应仅返回 [char] (本函数内部会包成 ConsoleKeyInfo)。
        生产场景下 ReadKey 返回的 ConsoleKeyInfo 在主机进程内传, 不存在跨边界问题。

    .PARAMETER Consumed
        [ref] 输出是否实际吞了字节 2/3 重组为方向键。

    .OUTPUTS
        合成后的 ConsoleKeyInfo, 或 $null(若字节 2 不是 '[')。
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = '仅读取/合成控制台按键, 不修改外部状态')]
    [CmdletBinding()]
    [OutputType([System.ConsoleKeyInfo])]
    param(
        [Parameter(Mandatory = $true)]
        [System.ConsoleKeyInfo]$FirstByte,

        [Parameter(Mandatory = $false)]
        [scriptblock]$NextKeyProvider,

        [Parameter(Mandatory = $true)]
        [ref]$Consumed
    )

    if (-not $NextKeyProvider) {
        $NextKeyProvider = { $Host.UI.RawUI.ReadKey("NoEcho, IncludeKeyDown") }
    }

    # 字节 1 不是 ESC 前缀, 不重组。
    # PS 5.1 的 ConsoleKeyInfo 5-arg 构造后 vK/char 恒为 0, 仅 Key 枚举被保留;
    # 真实 ReadKey API 会同时设置 vK=27, char=0x1B, Key=Escape。
    # 生产路径下三个字段都有, 这里只检查 Key=Escape (唯一可靠字段),
    # vK/char 作为额外安全检查, 但缺失时不重判 (只在 Key=Escape 就能代表是 ESC 按键)。
    if ($FirstByte.Key -ne [System.ConsoleKey]::Escape) {
        $Consumed.Value = $false
        return $null
    }
    # 额外检查: 若 vK/char 被 ReadKey 填上, 应是 27 / 0x1B; 都不是则不是 ESC 前缀。
    # 用 [int] 强转避免 PS 把 ushort/char=0 当空串, `-ne 0` 退化为字符串比较
    # VirtualKeyCode 是 ushort, 0/27 是合法值; PS 默认把 ushort 0 输出为空串, 需 [int] 强转
    $vk = [int]$FirstByte.VirtualKeyCode
    if ($vk -ne 0 -and $vk -ne 27) {
        $Consumed.Value = $false
        return $null
    }
    # Character 是 char, 0x00/0x1B 是合法值; PS 默认把 char 0 输出为空串, 需 [int] 强转
    $ch = [int]$FirstByte.Character
    if ($ch -ne 0 -and $ch -ne 27) {
        $Consumed.Value = $false
        return $null
    }

    # 字节 1 符合 ESC 前缀条件, 等待字节 2。
    # Provider 可返回 ConsoleKeyInfo (生产) 或 [char] (测试, 避免 .NET 跨边界丢字段)。
    $second = $null
    try {
        $second = & $NextKeyProvider
    } catch {
        $Consumed.Value = $false
        return $null
    }
    if ($null -eq $second) {
        $Consumed.Value = $false
        return $null
    }
    # 归一化为 char: 真实 ConsoleKeyInfo 取 .Character; 测试 [char] 直接用
    $secondChar = if ($second -is [System.ConsoleKeyInfo]) { [int][char]$second.Character } else { [int][char]$second }
    if ($secondChar -ne 91) {  # '[' = 91
        # 字节 2 不是 '[' → 这是真 ESC 按键, 但 ReadKey 已经消耗了字节 2。
        # ReadKey 协议本身不支持 unget, 字节 2 的副作用无法回滚, 这是底层 API 限制。
        # 仍返回 $null + Consumed=$false, 调用方把字节 1 当 ESC 处理, 字节 2 被吞 (实际少见场景)。
        $Consumed.Value = $false
        return $null
    }

    # 字节 3
    $third = $null
    try {
        $third = & $NextKeyProvider
    } catch {
        $Consumed.Value = $false
        return $null
    }
    if ($null -eq $third) {
        $Consumed.Value = $false
        return $null
    }
    $thirdChar = if ($third -is [System.ConsoleKeyInfo]) { [int][char]$third.Character } else { [int][char]$third }

    # A=上, B=下, C=右, D=左 (标准 ANSI CSI 方向键定义)
    $arrowMap = @{
        65 = [System.ConsoleKey]::UpArrow     # 'A' = 65
        66 = [System.ConsoleKey]::DownArrow   # 'B' = 66
        67 = [System.ConsoleKey]::RightArrow  # 'C' = 67
        68 = [System.ConsoleKey]::LeftArrow   # 'D' = 68
    }
    $finalKey = $arrowMap[$thirdChar]
    if (-not $finalKey) {
        $Consumed.Value = $false
        return $null
    }

    $Consumed.Value = $true
    # 5 参数构造: char, key, shift, alt, ctrl
    return [System.ConsoleKeyInfo]::new([char]0, $finalKey, $false, $false, $false)
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
        CSI 重组在调用方 (Invoke-MenuMachine) 完成, 此处只对已规范化的
        单一 ConsoleKeyInfo 做事件分发。

    .PARAMETER Context
        菜单上下文

    .PARAMETER Key
        原始 ReadKey 返回的 KeyInfo 对象 (已 CSI 重组)
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Context,

        [Parameter(Mandatory = $true)]
        [System.ConsoleKeyInfo]$Key
    )

    # VirtualKeyCode / Character 在不同来源下可能为 0/0 (如 5-arg 构造的重组后 key),
    # 唯一可靠字段是 Key 枚举 (CSIO 重路径) 或 vK 枚举 (Win API 路径)。
    # 导航判断统一走 Key 枚举, 避免 CSI 重组后 vK=0 失灵。
    $keyEnum = $Key.Key
    $vK = $Key.VirtualKeyCode
    $char = $Key.Character

    # 退出: Esc(Key=Escape 或 vK=27) 或 Q/q (char)
    if ($keyEnum -eq [System.ConsoleKey]::Escape -or $vK -eq 27 -or $char -eq 'q' -or $char -eq 'Q') {
        return $null
    }

    $visible = Get-VisibleMenuItems -Context $Context
    $count = $visible.Count
    if ($count -eq 0) { return $Context }

    # 上/下导航: 优先用 Key 枚举 (CSI 重组后 vK=0, char=0, 仅 Key 保留)
    if ($keyEnum -eq [System.ConsoleKey]::UpArrow -or $vK -eq 38) {  # Up
        $Context.SelectedIdx = ($Context.SelectedIdx - 1 + $count) % $count
        $Context.State = 'Selecting'
        return $Context
    }
    if ($keyEnum -eq [System.ConsoleKey]::DownArrow -or $vK -eq 40) {  # Down
        $Context.SelectedIdx = ($Context.SelectedIdx + 1) % $count
        $Context.State = 'Selecting'
        return $Context
    }

    # Enter: 确认
    if ($keyEnum -eq [System.ConsoleKey]::Enter -or $vK -eq 13) {
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

        # 字节级 CSI 重组: Windows Terminal + PS 5.1 下方向键拆为 3 个 ReadKey
        # (ESC + '[' + 'A/B/C/D'), 字节 1 单独看会被误判为 ESC 退出。
        # 重组需在 Send-MenuKey 之前完成, 避免下游误判。
        $consumed = $false
        $reassembled = ConvertTo-CsiArrowKey -FirstByte $key -Consumed ([ref]$consumed)
        if ($consumed -and $reassembled) {
            $key = $reassembled
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
