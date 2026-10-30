# Show-SessionManager.ps1 - tmux 全局操作菜单(分发器)
# 职责: 只做参数定义 + 主轨分发, 不含渲染逻辑。
# 唯一轨:
#   - GridView -> Invoke-GridViewSessionManager (PSTui Out-ConsoleGridView)
# 自研 ANSI 降级轨已于 2026-10-18 移除, 本分发器不再有第二条实现分支。
# 对外契约: 返回含 .Value 字段的 PSCustomObject
# (.Value = New/Remove/Ssh/Refresh), 或 $null(用户退出)。
# 注意: 分发器不使用 @PSBoundParameters 透传, 逐个显式传递。
#
# 方案 A (2026-10-29): tmux 管理器主界面改为真实会话列表(Show-TmuxSessionList),
# 本菜单降阶为轻量全局操作菜单(用户从会话列表按 ESC 进入), 不再提供"附着"动作 --
# 附着只能针对列表中明确选中的会话执行, 不作为脱离真实会话的独立菜单项。

function Show-SessionManager {
    <#
    .SYNOPSIS
        tmux 全局操作菜单(PSTui GridView 主轨)。

    .DESCRIPTION
        公开入口, 统一走 Invoke-GridViewSessionManager (PSTui Out-ConsoleGridView 表格视图)。
        显示 删除/创建/直连/刷新 四类全局动作, 会话为空时隐藏"删除"。
        "附着/恢复"不在此菜单: 它只能由用户在真实会话列表中选中会话后执行。
        调用前会断言 GridView 主轨可用, 不可用时抛出可定位的终止错误
        (自研 ANSI 降级轨已移除, 不存在备用渲染路径)。

    .PARAMETER HostName
        当前连接的主机名(用于 Title 显示)

    .PARAMETER TmuxVersion
        远程 tmux 版本号(无则传空串)

    .PARAMETER SessionCount
        当前会话总数(用于 Title 显示)

    .PARAMETER AttachedCount
        已附着会话数

    .PARAMETER DetachedCount
        已分离会话数

    .PARAMETER HasSessions
        会话列表是否非空(为 $false 时隐藏"删除"动作)

    .PARAMETER ExitLabel
        退出选项文字, 默认 "断开连接"

    .OUTPUTS
        选中的 PSCustomObject(.Value = New/Remove/Ssh/Refresh), 或 $null

    .EXAMPLE
        $action = Show-SessionManager -HostName 'debian' -TmuxVersion '3.3a' `
            -SessionCount 3 -AttachedCount 1 -DetachedCount 2 -HasSessions $true
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
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

    Assert-ConsoleUiReady -Feature 'tmux 全局操作菜单'

    return Invoke-GridViewSessionManager -HostName $HostName -TmuxVersion $TmuxVersion `
        -SessionCount $SessionCount -AttachedCount $AttachedCount -DetachedCount $DetachedCount `
        -HasSessions $HasSessions -ExitLabel $ExitLabel
}
