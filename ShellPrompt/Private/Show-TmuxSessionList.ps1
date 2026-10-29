# Show-TmuxSessionList.ps1 - tmux 会话列表选择菜单(分发器 + 刷新循环)
# 职责: 参数定义 + 主轨分发 + "刷新"语义, 不含具体渲染细节。
# 唯一轨:
#   - GridView -> Invoke-GridViewSessionList (PSTui Out-ConsoleGridView)
# 自研 ANSI 降级轨已于 2026-10-18 移除, 本分发器不再有第二条实现分支。
# 会话选择结果统一由 ConvertTo-TmuxSessionSelection 归一化为同一返回形状,
# 调用方(Connect-TmuxSession / Remove-TmuxSession)无需感知实现差异。
#
# 刷新语义(2026-10-18 补齐):
#   - 菜单打开期间不做定时轮询, 刷新完全由用户触发(列表中的"⟳ 刷新会话列表"项);
#   - 触发后重新拉取会话, 并重新弹出 GridView 表格(不改变主菜单结构);
#   - 刷新项通过哨兵值识别, 对调用方仍表现为"要么选中一个会话, 要么返回 $null"。

function ConvertTo-TmuxSessionSelection {
    <#
    .SYNOPSIS
        会话选择结果的统一归一化工厂(菜单契约的唯一出口)。

    .DESCRIPTION
        跨模块解耦点: 无论由哪一层菜单构造行对象, 最终都必须落成同一形状,
        否则调用方要写两套取值逻辑。这里固定四个字段:
          Value   = 纯会话名(下游执行 tmux attach / kill-session 的唯一入参)
          RawName = 同 Value, 兼容旧调用方 Connect-TmuxSession 的字段名
          Label   = 同 Value, 兼容旧调用方 Remove-TmuxSession 的字段名
          Desc    = 状态描述, 供上层提示使用
        注意 Label 必须是纯会话名而非 "[D] name", 否则 kill-session 会带上徽章文本。
        IsRefresh 恒为 $false, 用于与"刷新会话列表"特殊项区分。

    .PARAMETER Name
        会话名

    .PARAMETER Status
        会话状态(attached / detached), 为空时按 detached 处理

    .OUTPUTS
        PSCustomObject(.Value/.RawName/.Label/.Desc/.Status/.IsRefresh)

    .EXAMPLE
        ConvertTo-TmuxSessionSelection -Name 'btop' -Status 'detached'
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory = $false)]
        [string]$Status = ""
    )

    $statusText = if ($Status) { $Status } else { 'detached' }
    return [PSCustomObject]@{
        Value     = $Name
        RawName   = $Name
        Label     = $Name
        Desc      = "状态: $statusText"
        Status    = $statusText
        IsRefresh = $false
    }
}

function Show-TmuxSessionList {
    <#
    .SYNOPSIS
        tmux 会话列表选择菜单(PSTui GridView 主轨, 支持用户触发的原地刷新)。

    .DESCRIPTION
        私有入口, 统一走 Invoke-GridViewSessionList (PSTui Out-ConsoleGridView 表格视图)。
        对外契约: 返回归一化后的选择对象, 或 $null(用户退出)。
        传入 -SessionRefresher 时列表追加"⟳ 刷新会话列表"项; 用户选中后重新拉取
        会话并重新弹出表格, 直到用户选中会话或退出。
        调用前会断言 GridView 主轨可用, 不可用时抛出可定位的终止错误
        (自研 ANSI 降级轨已移除, 不存在备用渲染路径)。

    .PARAMETER HostName
        远程主机名(用于标题)
    .PARAMETER Sessions
        会话数组(元素含 Name 与 Status, 来自 Get-TmuxSessions)
    .PARAMETER Title
        菜单标题主体(主机名与计数部分由实现层拼接)
    .PARAMETER ExitLabel
        退出选项文字, 默认 "返回"
    .PARAMETER ShowStateBadge
        是否在表格 State 列显示 attached/detached 文本
    .PARAMETER SessionRefresher
        刷新脚本块, 返回新的会话数组; 未提供时列表不显示刷新项。

    .OUTPUTS
        含 .Value/.RawName/.Label 的 PSCustomObject, 或 $null(用户退出)

    .EXAMPLE
        $sel = Show-TmuxSessionList -HostName 'debian' -Sessions $sessions
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)][string]$HostName,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][array]$Sessions,
        [Parameter(Mandatory = $false)][string]$Title = "TMUX 会话列表",
        [Parameter(Mandatory = $false)][string]$ExitLabel = "返回",
        [Parameter(Mandatory = $false)][switch]$ShowStateBadge,
        [Parameter(Mandatory = $false)][scriptblock]$SessionRefresher
    )

    if (-not $Sessions -or $Sessions.Count -eq 0) {
        Write-Warning "没有可用的 tmux 会话"
        return $null
    }

    Assert-ConsoleUiReady -Feature 'tmux 会话列表菜单'

    $current = $Sessions
    while ($true) {
        $selection = Invoke-TmuxSessionListView -Sessions $current -HostName $HostName -Title $Title `
            -ExitLabel $ExitLabel -ShowStateBadge:$ShowStateBadge `
            -AllowRefresh:([bool]$SessionRefresher)

        if ($null -eq $selection) { return $null }
        if (-not $selection.IsRefresh) { return $selection }

        # 用户触发的刷新: 重新拉取会话, 然后重新弹出 GridView 表格。
        # 不引入定时器/后台轮询, 刷新时机完全由用户决定。
        # 注: GridView 每次以独立弹窗渲染, 无需 ANSI 轨那样的清屏重绘。
        $current = Get-TmuxRefreshedSession -SessionRefresher $SessionRefresher
        if ($current.Count -eq 0) {
            Write-Warning "没有可用的 tmux 会话"
            return $null
        }
    }
}

function Invoke-TmuxSessionListView {
    <#
    .SYNOPSIS
        渲染一帧 tmux 会话列表视图(GridView 主轨), 并返回归一化选择结果。

    .DESCRIPTION
        Show-TmuxSessionList 的单帧渲染实现: 走 GridView 表格。
        标题统一拼接"会话 N 附 X / 分 Y"计数, 状态文案统一走
        Get-TmuxSessionStateText, 保证语义一致。
        选中"刷新"项时返回 ConvertTo-TmuxRefreshSelection 构造的对象
        (IsRefresh = $true), 由上层重新拉取会话后再次调用本函数。

    .PARAMETER Sessions
        会话数组(元素含 Name 与 Status)

    .PARAMETER HostName
        远程主机名(用于标题)

    .PARAMETER Title
        菜单标题主体

    .PARAMETER ExitLabel
        退出选项文字

    .PARAMETER ShowStateBadge
        是否显示 attached/detached 状态文本

    .PARAMETER AllowRefresh
        是否追加"⟳ 刷新会话列表"项

    .OUTPUTS
        归一化选择 PSCustomObject, 或 $null(用户退出)

    .EXAMPLE
        $sel = Invoke-TmuxSessionListView -Sessions $sessions -HostName 'debian'
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][array]$Sessions,
        [Parameter(Mandatory = $true)][string]$HostName,
        [Parameter(Mandatory = $false)][string]$Title = "TMUX 会话列表",
        [Parameter(Mandatory = $false)][string]$ExitLabel = "返回",
        [Parameter(Mandatory = $false)][switch]$ShowStateBadge,
        [Parameter(Mandatory = $false)][switch]$AllowRefresh
    )

    $summary = Get-TmuxSessionSummary -Sessions $Sessions

    return Invoke-GridViewSessionList -Sessions $Sessions -HostName $HostName -Title $Title `
        -ExitLabel $ExitLabel -ShowStateBadge:$ShowStateBadge -AllowRefresh:$AllowRefresh `
        -TitleSuffix $summary.TitleSuffix
}
