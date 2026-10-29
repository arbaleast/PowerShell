# Show-SessionManager.ps1 - tmux 会话动作选择菜单(分发器)
# 职责: 只做参数定义 + 主轨分发, 不含渲染逻辑。
# 唯一轨:
#   - GridView -> Invoke-GridViewSessionManager (PSTui Out-ConsoleGridView)
# 自研 ANSI 降级轨已于 2026-10-18 移除, 本分发器不再有第二条实现分支。
# 对外契约: 返回含 .Value 字段的 PSCustomObject
# (.Value = Attach/New/Remove/Ssh/Refresh), 或 $null(用户退出)。
# 注意: 分发器不使用 @PSBoundParameters 透传, 逐个显式传递。

function Show-SessionManager {
    <#
    .SYNOPSIS
        tmux 会话动作选择菜单(PSTui GridView 主轨)。

    .DESCRIPTION
        公开入口, 统一走 Invoke-GridViewSessionManager (PSTui Out-ConsoleGridView 表格视图)。
        显示 附着/创建/删除/直连/刷新 五类动作, 会话为空时隐藏"附着"和"删除"。
        调用前会断言 GridView 主轨可用, 不可用时抛出可定位的终止错误
        (自研 ANSI 降级轨已移除, 不存在备用渲染路径)。

    .PARAMETER HostName
        当前连接的主机名(用于 Title 显示 + 状态标注)

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
        选中的 PSCustomObject(.Value = Attach/New/Remove/Ssh/Refresh), 或 $null

    .EXAMPLE
        $action = Show-SessionManager -HostName 'debian' -TmuxVersion '3.3a' `
            -SessionCount 3 -AttachedCount 1 -DetachedCount 2 -HasSessions $true
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

    Assert-ConsoleUiReady -Feature 'tmux 会话动作菜单'

    return Invoke-GridViewSessionManager -HostName $HostName -TmuxVersion $TmuxVersion `
        -SessionCount $SessionCount -AttachedCount $AttachedCount -DetachedCount $DetachedCount `
        -HasSessions $HasSessions -ExitLabel $ExitLabel
}
