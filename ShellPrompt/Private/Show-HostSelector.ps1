# Show-HostSelector.ps1 - 主机选择交互式菜单(分发器)
# 职责: 只做参数定义 + 就绪断言 + 业务装配, 不含渲染逻辑。
# 唯一轨:
#   - Terminal.Gui v2 (独立 ALC) -> Invoke-TguiHostSelector
# 原 PSTui GridView 轨已于 2026-10-30 随 Modules/PSTui 删除一并移除。
# 对外契约(不变): 返回含 .Value 字段的 PSCustomObject, 或 $null(用户退出)。
# 注意: 分发器不使用 @PSBoundParameters 透传, 否则分发专用参数会被
#       泄漏进实现函数, 造成参数绑定错误。逐个显式传递。

function Show-HostSelector {
    <#
    .SYNOPSIS
        主机选择交互式菜单(Terminal.Gui v2 主轨)。

    .DESCRIPTION
        公开入口, 走 Invoke-TguiHostSelector(ALC 原生 Terminal.Gui v2 表格视图
        + 过滤输入框)。调用前会断言交互式 UI 主轨可用, 不可用时抛出可定位
        的终止错误。
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

    $rows = @(Get-HostSelectorRow -Hosts $Hosts -LastHost $LastHost)

    # Title 区追加单行天气(顶部), 端点选择与清洗细节封装在 Get-WttrTitleSuffix 内
    $wttrSuffix = Get-WttrTitleSuffix

    # ExitLabel 由调用方作为退出提示文案传入(Pester / Start-TmuxSession 消费),
    # 渲染由提示条承担, 本分发器不重复渲染。
    $selected = Invoke-TguiHostSelector -Rows $rows -Title "$Title ($($Hosts.Count))$wttrSuffix"
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
