# New-StatusBadge.ps1 - 状态徽章构造器
# 用于可视化对象状态: SSH 连接 / tmux 会话 / 网络错误等
# 6 种状态: Online(绿) / Attached(蓝) / Detached(灰) / NetworkError(红) / Pending(黄) / Disabled(暗)


function New-StatusBadge {
    <#
    .SYNOPSIS
        构造一个状态徽章对象(纯数据, 不渲染)

    .DESCRIPTION
        返回 PSCustomObject, 持有 Glyph(符号) / Color(ANSI 转义) / Text(说明) / Status(枚举)
        渲染时由调用方拼接(典型用法: 嵌入 HeaderBadges 或菜单项 Badge 字段)

    .PARAMETER Status
        状态枚举: Online / Attached / Detached / NetworkError / Pending / Disabled

    .PARAMETER Text
        自定义说明文字(未指定时取状态默认描述)

    .EXAMPLE
        $badge = New-StatusBadge -Status Online
        $badge = New-StatusBadge -Status NetworkError -Text "连接超时"
    #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    [OutputType([PSCustomObject])]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseBOMForUnicodeEncodedFile', '')]
param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Online', 'Attached', 'Detached', 'NetworkError', 'Pending', 'Disabled', 'Warning')]
        [string]$Status,

        [Parameter(Mandatory = $false)]
        [string]$Text
    )

    # 预热颜色(走缓存, 0 命中回退到硬编码)
    $green   = Get-CachedConfig -Section 'Colors' -Key 'FreshGreen' -Default "`e[38;2;137;209;133m"
    $sage    = Get-CachedConfig -Section 'Colors' -Key 'SageGreen'  -Default "`e[38;2;159;177;159m"
    $gray    = Get-CachedConfig -Section 'Colors' -Key 'MidGray'    -Default "`e[38;2;100;100;100m"
    $dark    = Get-CachedConfig -Section 'Colors' -Key 'DarkGray'   -Default "`e[38;2;50;50;50m"
    $rst     = Get-CachedConfig -Section 'Colors' -Key 'Rst'        -Default "`e[0m"

    # 蓝色和黄/红不在默认 Colors 域, 走硬编码(项目目前不需要用户可配置)
    $blue    = "`e[38;2;100;180;255m"
    $yellow  = "`e[38;2;230;180;80m"
    $red     = "`e[38;2;220;100;100m"

    # 状态映射表: Glyph + Color + 默认 Text
    $map = @{
        Online       = @{ Glyph = '●'; Color = $green;  Default = 'ready' }
        Attached     = @{ Glyph = '●'; Color = $blue;   Default = 'attached' }
        Detached     = @{ Glyph = '○'; Color = $gray;   Default = 'detached' }
        NetworkError = @{ Glyph = '✗'; Color = $red;    Default = 'unreachable' }
        Pending      = @{ Glyph = '◐'; Color = $yellow; Default = 'pending' }
        Warning      = @{ Glyph = '!'; Color = $yellow; Default = 'warning' }
        Disabled     = @{ Glyph = '×'; Color = $dark;   Default = 'disabled' }
    }

    $entry = $map[$Status]
    $text = if ($Text) { $Text } else { $entry.Default }

    return [PSCustomObject]@{
        Status = $Status
        Glyph  = $entry.Glyph
        Color  = $entry.Color
        Text   = $text
        Rst    = $rst
    }
}

function Format-StatusBadge {
    <#
    .SYNOPSIS
        将状态徽章格式化为单行 ANSI 字符串(可直接输出)

    .PARAMETER Badge
        New-StatusBadge 返回的徽章对象

    .EXAMPLE
        Format-StatusBadge -Badge (New-StatusBadge -Status Attached)
        # 返回: "[● attached]"  (含 ANSI 颜色)
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Badge
    )
    return "$($Badge.Color)$($Badge.Glyph) $($Badge.Text)$($Badge.Rst)"
}
