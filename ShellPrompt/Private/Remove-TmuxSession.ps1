# Remove-TmuxSession.ps1 - 删除远程 tmux 会话


function Remove-TmuxSession {
    <#
    .SYNOPSIS
        通过交互式菜单选择并删除远程 tmux 会话

    .DESCRIPTION
        展示远程主机上的 tmux 会话列表，用户选择后通过 SSH kill-session 删除目标会话。
        选择与删除之间强制插入一次 Read-SpectreConfirm 阻断式二次确认：
        tmux kill-session 不可逆，且选择菜单本身不含红色警示（GridView 轨无行级配色），
        因此二次确认是防止误删的唯一屏障，两条 UI 后端轨共用。

        2026-10-30 TGUI 迁移: 会话选定之后的"二次确认 + kill-session"整体委托给
        Invoke-TmuxSessionDeletion —— 它是删除屏障的**唯一实现**, TGUI 仪表盘
        (表格里直接删除选中行)走同一条路径, 屏障无法被绕过。

    .PARAMETER HostName
        远程主机名

    .PARAMETER Sessions
        会话列表（由 Get-TmuxSessions 返回的 PSCustomObject 数组）

    .EXAMPLE
        Remove-TmuxSession -HostName myserver -Sessions $sessions
    #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    [OutputType([void])]
param(
        [Parameter(Mandatory = $true)]
        [string]$HostName,

        [Parameter(Mandatory = $true)]
        [array]$Sessions
    )
    if ($PSCmdlet.ShouldProcess("tmux session on $HostName", "Perform Remove-TmuxSession")) { } else { return  }

    if ($Sessions.Count -eq 0) {
        Write-Warning "没有可删除的会话"
        return
    }

    # 菜单分发: 统一走 GridView 主轨; 下方的 Read-SpectreConfirm 二次确认
    # 与 kill-session 逻辑 —— 它才是防误删的唯一屏障。
    # -SessionRefresher: 删除前允许用户在列表内重新拉取会话(强制绕过 TTL 缓存),
    # 避免基于过期列表误删; 刷新不改变任何删除语义, 二次确认仍然必经。
    # 刷新失败口径(2026-10-29 审计, 与 Start-TmuxSession / Connect 侧统一):
    #   探测命令以 `; true` 结尾, 远端退出码恒为 0; 退出码非 0 必然是 SSH 连接/传输层
    #   失败。命中"退出码非 0 或网络错误模式"即抛异常, 由 Show-TmuxSessionList 捕获 ->
    #   警告 + 保留原列表 + 允许重试; 不命中则返回会话数组(可能为空数组, 那是
    #   "确实没有会话"而非失败)。这样"查询失败"与"查询成功但没有会话"不再混为一谈。
    $selected = Show-TmuxSessionList -HostName $HostName -Sessions $Sessions `
        -Title "删除 TMUX 会话" -ExitLabel "取消" -ShowStateBadge `
        -SessionRefresher {
            $refreshedData = Get-TmuxSessions -HostName $HostName -Force
            if ($refreshedData.ExitCode -ne 0 -or $refreshedData.NetworkError) {
                throw "未能获取 $HostName 的 tmux 会话列表 (ssh 退出码: $($refreshedData.ExitCode))"
            }
            $refreshedData.Sessions
        }
    if ($null -eq $selected) { return }

    # 二次确认 + kill-session 全部委托给 Invoke-TmuxSessionDeletion ——
    # 二次确认是防误删的唯一屏障, 逻辑必须只有一份(TGUI 仪表盘删除选中行时
    # 走同一条路径)。-Confirm:$false: 外层 ShouldProcess 已经问过一次,
    # 这里不再重复弹确认, 保持旧链路的提示次数不变。
    Invoke-TmuxSessionDeletion -HostName $HostName -SessionName ([string]$selected.Value) -Confirm:$false
}
