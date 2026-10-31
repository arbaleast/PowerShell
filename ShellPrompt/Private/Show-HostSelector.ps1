# Show-HostSelector.ps1 - 主机选择交互式菜单(分发器)
# 职责: 只做参数定义 + 就绪断言 + 业务装配, 不含渲染逻辑。
# 唯一轨:
#   - SSH 主机仪表盘(多区域: 分类导航 / 主机列表 / 详情卡片 / 快捷键栏)
#     -> Show-SshHostDashboard -> Invoke-SshHostDashboard
# 历史(保留可用, 不是默认路径):
#   - Invoke-TguiHostSelector(单表格主机选择器)仍在模块内, 未删除;
#     仪表盘轨取代它成为默认呈现, 旧实现可随时回退。
# 对外契约(不变): 返回含 .Value 字段的 PSCustomObject, 或 $null(用户退出)。
# 注意: 分发器不使用 @PSBoundParameters 透传, 否则分发专用参数会被
#       泄漏进实现函数, 造成参数绑定错误。逐个显式传递。

function Show-HostSelector {
    <#
    .SYNOPSIS
        主机选择交互式菜单(Terminal.Gui v2 主机仪表盘)。

    .DESCRIPTION
        公开入口, 走 Show-SshHostDashboard(多区域 SSH 主机仪表盘:
        顶部分类导航 / 左侧主机列表 / 右侧详情卡片 / 底部快捷键栏)。
        调用前会断言交互式 UI 主轨可用, 不可用时抛出可定位的终止错误。
        业务装配(SSH 配置主机读取、LastHost 置顶、Disabled 阻断)保留在此层,
        UI 层不承载任何 SSH 业务逻辑。

    .PARAMETER Hosts
        主机名数组(来自 Get-SshConfigHosts)

    .PARAMETER LastHost
        上次使用的主机名(用于置顶 + 状态标注), 默认取 $script:Config.SSH.LastHost

    .PARAMETER Title
        菜单标题, 默认 "SSH 主机选择器"

    .PARAMETER ExitLabel
        退出选项文字, 默认 "退出"

    .OUTPUTS
        选中的 PSCustomObject(.Value = 主机名), 或 $null(用户退出)

    .EXAMPLE
        $selected = Show-HostSelector -Hosts (Get-SshConfigHosts)
        if ($selected) { $script:Config.SSH.LastHost = $selected.Value }
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    # ExitLabel 由调用方作为退出提示文案传入(Pester / Start-TmuxSession 消费),
    # 渲染由 Terminal.Gui 提示条承担, 本分发器不重复渲染。显式抑制 PSSA 误报。
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'ExitLabel')]
    param(
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

    Assert-ConsoleUiReady -Feature 'SSH 主机选择器'

    if (-not $Hosts -or $Hosts.Count -eq 0) {
        Write-Warning "SSH 配置中未找到任何主机，请先在 ~/.ssh/config 中配置主机"
        return $null
    }

    if (-not $LastHost -and $script:Config -and $script:Config.SSH) {
        $LastHost = $script:Config.SSH.LastHost
    }

    # Title 区追加单行天气(顶部), 端点选择与清洗细节封装在 Get-WttrTitleSuffix 内
    $wttrSuffix = Get-WttrTitleSuffix

    # ExitLabel 由调用方作为退出提示文案传入(Pester / Start-TmuxSession 消费),
    # 渲染由提示条承担, 本分发器不重复渲染。
    $selected = Show-SshHostDashboard -Hosts $Hosts -LastHost $LastHost -Title $Title -TitleSuffix $wttrSuffix
    if ($null -eq $selected) {
        return $null
    }

    # 不支持行级置灰, Disabled 行选中后的阻断兜底
    if ($selected.Disabled) {
        Write-Warning "该项当前不可用: $($selected.Host)"
        return $null
    }

    return $selected
}
