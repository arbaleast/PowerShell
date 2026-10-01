# Show-HostSelector.ps1 - 主机选择交互式菜单
# 借鉴 ctty 风格: 实时键盘过滤 / LastHost 徽章 / 状态徽章
# 重构后: 仅负责数据准备(主机排序/LastHost 置顶/Exit 项), 委托 Invoke-MenuMachine 处理交互

. "$PSScriptRoot\New-AnsiLayout.ps1"
. "$PSScriptRoot\Write-MenuItem.ps1"
. "$PSScriptRoot\New-StatusBadge.ps1"
. "$PSScriptRoot\Invoke-MenuMachine.ps1"

function Show-HostSelector {
    <#
    .SYNOPSIS
        主机选择交互式菜单(支持实时键盘过滤)

    .DESCRIPTION
        替代 Invoke-ConsoleMenu 在主机选择场景的用法。
        实时过滤(Q1=A): 每次击键立即重绘过滤后的列表。
        LastHost 徽章: 上次使用的主机在列表顶部显示绿色 ready 徽章。
        ExitLabel 默认 "退出", 可自定义。
        P1 重构后: 委托 Invoke-MenuMachine 处理键盘事件分发。

    .PARAMETER Hosts
        主机名数组(来自 Get-SshConfigHosts)

    .PARAMETER LastHost
        上次使用的主机名(用于置顶 + 显示徽章), 默认取 $script:Config.SSH.LastHost

    .PARAMETER Title
        菜单标题, 默认 "SSH 主机选择器"

    .PARAMETER ExitLabel
        退出选项文字, 默认 "退出"

    .EXAMPLE
        $selected = Show-HostSelector -Hosts (Get-SshConfigHosts)
        if ($selected) { $script:Config.SSH.LastHost = $selected.Value }
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseBOMForUnicodeEncodedFile', '')]    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$Hosts,

        [Parameter(Mandatory = $false)]
        [string]$LastHost = "",

        [Parameter(Mandatory = $false)]
        [string]$Title = "SSH 主机选择器",

        [Parameter(Mandatory = $false)]
        [string]$ExitLabel = "退出"
    )

    if (-not $Hosts -or $Hosts.Count -eq 0) {
        Write-Warning "SSH 配置中未找到任何主机，请先在 ~/.ssh/config 中配置主机"
        return $null
    }

    # 预解析颜色(走缓存)
    $primary = Get-CachedConfig -Section 'Colors' -Key 'FreshGreen' -Default "`e[38;2;137;209;133m"
    $accent  = Get-CachedConfig -Section 'Colors' -Key 'SageGreen'  -Default "`e[38;2;159;177;159m"
    $muted   = Get-CachedConfig -Section 'Colors' -Key 'MidGray'    -Default "`e[38;2;100;100;100m"
    $rst     = Get-CachedConfig -Section 'Colors' -Key 'Rst'        -Default "`e[0m"
    $colors = @{ Primary = $primary; Accent = $accent; Muted = $muted; Rst = $rst }

    # 取 LastHost(参数优先, 否则从配置)
    if (-not $LastHost -and $script:Config -and $script:Config.SSH) {
        $LastHost = $script:Config.SSH.LastHost
    }

    # 构造菜单项: LastHost 置顶 + 绿色 ready 徽章
    $orderedHosts = @($Hosts)
    if ($LastHost -and ($orderedHosts -contains $LastHost)) {
        $orderedHosts = @($LastHost) + @($orderedHosts | Where-Object { $_ -ne $LastHost })
    }

    $allItems = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($h in $orderedHosts) {
        $isLast = ($h -eq $LastHost)
        $desc = if ($isLast) { "上次使用" } else { "SSH 远程主机" }
        $badge = if ($isLast) { New-StatusBadge -Status Online -Text "last" } else { $null }
        $allItems.Add((New-MenuItem -Label $h -Desc $desc -Value $h -Badge $badge))
    }
    $exitItem = New-MenuItem -Label $ExitLabel -Desc "return to local terminal" -Value $null
    $allItems.Add($exitItem)

    # Header 徽章: 主机数 + LastHost 状态
    $headerBadges = @(
        "$($Hosts.Count) 主机",
        (New-StatusBadge -Status Online -Text "ssh ready")
    )

    # 构造布局
    $layout = New-AnsiLayout -Title $Title -HeaderBadges $headerBadges -Colors $colors

    # Footer: 快捷键提示
    $layout.Footer[0] = "  ${primary}+$($layout.HLine)--${rst}"
    $layout.Footer[1] = "  ${muted}↑↓ 导航  Enter 确认  Esc/Q 退出  Backspace 清空过滤  Ctrl+U 全清${rst}"

    # 构造上下文
    $ctx = New-MenuContext -AllItems $allItems -ExitItem $exitItem -AllowFilter $true

    # 委托 MenuMachine
    return Invoke-MenuMachine -Context $ctx -Layout $layout -Colors $colors -ExitLabel $ExitLabel
}
