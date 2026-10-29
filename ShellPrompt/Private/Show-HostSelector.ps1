# Show-HostSelector.ps1 - 主机选择交互式菜单(分发器)
# 职责: 只做参数定义 + 主轨分发, 不含渲染逻辑。
# 唯一轨:
#   - GridView -> Invoke-GridViewHostSelector (PSTui Out-ConsoleGridView)
# 自研 ANSI 降级轨已于 2026-10-18 移除, 本分发器不再有第二条实现分支。
# 对外契约: 返回含 .Value 字段的 PSCustomObject, 或 $null(用户退出)。
# 注意: 分发器不使用 @PSBoundParameters 透传, 否则分发专用参数会被
#       泄漏进实现函数, 造成参数绑定错误。逐个显式传递。

function Show-HostSelector {
    <#
    .SYNOPSIS
        主机选择交互式菜单(PSTui GridView 主轨)。

    .DESCRIPTION
        公开入口, 统一走 Invoke-GridViewHostSelector (PSTui Out-ConsoleGridView 表格视图)。
        调用前会断言 GridView 主轨可用, 不可用时抛出可定位的终止错误
        (自研 ANSI 降级轨已移除, 不存在备用渲染路径)。

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

    return Invoke-GridViewHostSelector -Hosts $Hosts -LastHost $LastHost -Title $Title -ExitLabel $ExitLabel
}
