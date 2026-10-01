# Show-SessionManager.ps1 - tmux 会话动作选择菜单
# 借鉴 ctty 风格: 动态帮助面板 / 状态徽章 / 描述行内联
# 委托: New-AnsiLayout + Write-MenuItem + New-StatusBadge + Invoke-MenuMachine + New-DynamicHelpPanel

. "$PSScriptRoot\New-AnsiLayout.ps1"
. "$PSScriptRoot\Write-MenuItem.ps1"
. "$PSScriptRoot\New-StatusBadge.ps1"
. "$PSScriptRoot\Invoke-MenuMachine.ps1"
. "$PSScriptRoot\New-DynamicHelpPanel.ps1"

function Show-SessionManager {
    <#
    .SYNOPSIS
        tmux 会话动作选择菜单(替代原 Start-TmuxSession 中的内联动作菜单)

    .DESCRIPTION
        显示 4-5 个动作: 附着/恢复 / 删除 / 新建 / 直连 / 刷新。
        会话为空时自动隐藏"附着"和"删除"项。
        选中项变化时, Footer 帮助面板实时更新(动态帮助)。
        每次菜单循环重新探测远端会话状态(与原实现一致, Q6=A)。

    .PARAMETER HostName
        当前连接的主机名(用于 Title 显示 + 状态徽章)

    .PARAMETER TmuxVersion
        远程 tmux 版本号(无则传空串)

    .PARAMETER SessionCount
        当前会话总数(用于 Title 显示)

    .PARAMETER AttachedCount
        已附着会话数

    .PARAMETER DetachedCount
        已分离会话数

    .PARAMETER HasSessions
        会话列表是否非空(为 $false 时隐藏"附着/删除"动作)

    .PARAMETER ExitLabel
        退出选项文字, 默认 "断开连接"

    .OUTPUTS
        选中的动作项 PSCustomObject(Label/Value 字段), 或 $null(用户退出)

    .EXAMPLE
        $action = Show-SessionManager -HostName "debian" -TmuxVersion "3.3a" `
            -SessionCount 3 -AttachedCount 1 -DetachedCount 2 -HasSessions $true
        if ($action -and $action.Label -eq "附着/恢复 tmux 会话") { ... }
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseBOMForUnicodeEncodedFile', '')]
param(
        [Parameter(Mandatory = $true)]
        [string]$HostName,

        [Parameter(Mandatory = $false)]
        [string]$TmuxVersion = "",

        [Parameter(Mandatory = $false)]
        [int]$SessionCount = 0,

        [Parameter(Mandatory = $false)]
        [int]$AttachedCount = 0,

        [Parameter(Mandatory = $false)]
        [int]$DetachedCount = 0,

        [Parameter(Mandatory = $false)]
        [bool]$HasSessions = $false,

        [Parameter(Mandatory = $false)]
        [string]$ExitLabel = "断开连接"
    )

    # 预解析颜色
    $primary = Get-CachedConfig -Section 'Colors' -Key 'FreshGreen' -Default "`e[38;2;137;209;133m"
    $accent  = Get-CachedConfig -Section 'Colors' -Key 'SageGreen'  -Default "`e[38;2;159;177;159m"
    $muted   = Get-CachedConfig -Section 'Colors' -Key 'MidGray'    -Default "`e[38;2;100;100;100m"
    $rst     = Get-CachedConfig -Section 'Colors' -Key 'Rst'        -Default "`e[0m"
    $colors = @{ Primary = $primary; Accent = $accent; Muted = $muted; Rst = $rst }

    # 构造菜单项: 会话为空时隐藏"附着/删除"
    $allItems = [System.Collections.Generic.List[PSCustomObject]]::new()
    if ($HasSessions) {
        $allItems.Add((New-MenuItem -Label "附着/恢复 tmux 会话" -Desc "选择并附着到远程 tmux 会话" -Value "Attach"))
    }
    $allItems.Add((New-MenuItem -Label "创建新 tmux 会话" -Desc "在远程主机上创建新的 tmux 会话" -Value "New"))
    if ($HasSessions) {
        $allItems.Add((New-MenuItem -Label "删除 tmux 会话" -Desc "删除远程主机上的 tmux 会话" -Value "Remove"))
    }
    $allItems.Add((New-MenuItem -Label "直接 SSH 登录" -Desc "不使用 tmux, 直接 SSH 登录" -Value "Ssh"))
    $allItems.Add((New-MenuItem -Label "刷新会话列表" -Desc "重新获取远程 tmux 会话状态" -Value "Refresh"))

    $exitItem = New-MenuItem -Label $ExitLabel -Desc "return to local terminal" -Value $null

    # Header 徽章: 主机 + tmux 版本 + 会话统计
    $titleSuffix = "TMUX 管理器 [$HostName]"
    $headerBadges = @()
    if ($TmuxVersion) {
        $headerBadges += (New-StatusBadge -Status Online -Text "tmux $TmuxVersion")
    } else {
        $headerBadges += (New-StatusBadge -Status Detached -Text "tmux?")
    }
    $headerBadges += "会话: $SessionCount (附=$AttachedCount 分=$DetachedCount)"

    # 构造布局
    $layout = New-AnsiLayout -Title $titleSuffix -HeaderBadges $headerBadges -Colors $colors

    # 自定义渲染器: 主菜单 + 动态帮助面板
    $renderer = {
        param($Layout, $VisibleItems, $SelectedIdx, $Filter, $Colors, $ExitLabel, $ExitSelected, $ExitUnselected, $ExitItem)
        $primary = $Colors.Primary
        $accent = $Colors.Accent
        $muted = $Colors.Muted
        $rst = $Colors.Rst

        $Layout.Main.Clear()
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

        # 动态帮助: 根据当前选中项切换
        $sel = $VisibleItems[$SelectedIdx]
        $helpEntries = Get-SessionActionHelp -ActionLabel $sel.Label
        $helpStr = New-DynamicHelpPanel -Entries $helpEntries -Colors $Colors

        $Layout.Footer[0] = "  ${primary}+$($Layout.HLine)--${rst}"
        $Layout.Footer[1] = "  ${helpStr}"
    }

    # 构造上下文(此菜单禁用过滤)
    $ctx = New-MenuContext -AllItems $allItems -ExitItem $exitItem -AllowFilter $false

    return Invoke-MenuMachine -Context $ctx -Layout $layout -Colors $colors -ExitLabel $ExitLabel -OnRender $renderer
}
