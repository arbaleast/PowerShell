# Write-MenuItem.ps1 - 菜单项单行渲染器
# 支持 3 种视觉态: 选中 / 未选中 / 禁用; 选中态附加焦点边框
# 颜色统一走 Get-CachedConfig 预热缓存; 输出为完整 ANSI 字符串, 由调用方写入控制台


function New-MenuItem {
    <#
    .SYNOPSIS
        构造一个菜单项对象(纯数据, 不渲染)

    .DESCRIPTION
        菜单项是 PSCustomObject, 持有 Label / Desc / Value / Disabled / StyleOverride 等字段。
        渲染前由 New-MenuItem 构造, 渲染时由 Write-MenuItem 消费。

    .PARAMETER Label
        主显示文本

    .PARAMETER Desc
        描述文本(渲染时内联在主文本右侧, 或作为子提示)

    .PARAMETER Value
        选中时返回的值(未指定则返回 Label)

    .PARAMETER Disabled
        是否禁用(禁用项不可选中, 渲染为暗灰)

    .PARAMETER Badge
        附加徽章(状态徽章对象, 渲染在主文本左侧)

    .EXAMPLE
        $item = New-MenuItem -Label "debian" -Desc "SSH 远程主机" -Badge (New-StatusBadge -Status Online)
    #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    [OutputType([PSCustomObject])]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseBOMForUnicodeEncodedFile', '')]
param(
        [Parameter(Mandatory = $true)]
        [string]$Label,

        [Parameter(Mandatory = $false)]
        [string]$Desc = "",

        [Parameter(Mandatory = $false)]
        [object]$Value,

        [Parameter(Mandatory = $false)]
        [bool]$Disabled = $false,

        [Parameter(Mandatory = $false)]
        [PSCustomObject]$Badge
    )
    $val = if ($PSBoundParameters.ContainsKey('Value')) { $Value } else { $Label }
    return [PSCustomObject]@{
        Label    = $Label
        Desc     = $Desc
        Value    = $val
        Disabled = $Disabled
        Badge    = $Badge
    }
}

function Write-MenuItem {
    <#
    .SYNOPSIS
        渲染单个菜单项为完整 ANSI 字符串

    .DESCRIPTION
        返回单个字符串, 不直接输出到控制台(便于调用方批量预构 + 选择性写入)。
        视觉态: Selected(主色 + 焦点箭头) / Normal(弱化色) / Disabled(暗灰 + 斜杠)

    .PARAMETER Item
        New-MenuItem 构造的菜单项对象

    .PARAMETER Index
        项序号(0-based), 用于显示 [01] [02] ... 快捷键提示

    .PARAMETER IsSelected
        是否为当前选中项

    .PARAMETER Colors
        颜色覆盖表(主色/强调色/弱化色/边框色)

    .EXAMPLE
        $line = Write-MenuItem -Item $item -Index 0 -IsSelected $true
        Write-AnsiLine -Line 5 -Text $line
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Item,

        [Parameter(Mandatory = $true)]
        [int]$Index,

        [Parameter(Mandatory = $true)]
        [bool]$IsSelected,

        [Parameter(Mandatory = $false)]
        [hashtable]$Colors
    )

    # 颜色预解析: 走缓存, 0 命中回退到硬编码
    $primary = if ($Colors -and $Colors.Primary) { $Colors.Primary } else { Get-CachedConfig -Section 'Colors' -Key 'FreshGreen' -Default "`e[38;2;137;209;133m" }
    $accent  = if ($Colors -and $Colors.Accent)  { $Colors.Accent  } else { Get-CachedConfig -Section 'Colors' -Key 'SageGreen'  -Default "`e[38;2;159;177;159m" }
    $muted   = if ($Colors -and $Colors.Muted)   { $Colors.Muted   } else { Get-CachedConfig -Section 'Colors' -Key 'MidGray'    -Default "`e[38;2;100;100;100m" }
    $rst     = if ($Colors -and $Colors.Rst)     { $Colors.Rst     } else { Get-CachedConfig -Section 'Colors' -Key 'Rst' -Default "`e[0m" }

    $key = ($Index + 1).ToString().PadLeft(2, '0')
    $badgeStr = ""
    if ($Item.Badge) {
        $badgeStr = "$($Item.Badge.Glyph) "
    }

    # 禁用态: 暗灰 + 斜杠前缀
    if ($Item.Disabled) {
        return "  ${primary}|${rst}  ${muted}/${rst} ${muted}[${key}]${rst} ${muted}${badgeStr}$($Item.Label)${rst}"
    }

    # 选中态: 主色 + 焦点箭头 + 边框字符
    if ($IsSelected) {
        $descPart = if ($Item.Desc) { "  ${muted}$($Item.Desc)${rst}" } else { "" }
        return "  ${primary}|${rst}  ${rst}>${rst} ${primary}[${key}]${rst} ${primary}${badgeStr}$($Item.Label)${rst}${descPart}"
    }

    # 未选中态: 弱化色
    $descPart = if ($Item.Desc) { "  ${muted}$($Item.Desc)${rst}" } else { "" }
    return "  ${primary}|${rst}  ${muted} ${rst} ${muted}[${key}]${rst} ${muted}${badgeStr}$($Item.Label)${rst}${descPart}"
}
