# Connect-TmuxSession.ps1 - 附着/恢复远程 tmux 会话

function Connect-TmuxSession {
    <#
    .SYNOPSIS
        通过交互式菜单选择并附着到远程 tmux 会话

    .DESCRIPTION
        展示远程主机上的 tmux 会话列表，用户选择后通过 SSH attach 到目标会话。
        已附着会话标记 [A]，已分离会话标记 [D]。

    .PARAMETER HostName
        远程主机名

    .PARAMETER Sessions
        会话列表（由 Get-TmuxSessions 返回的 PSCustomObject 数组）

    .EXAMPLE
        Connect-TmuxSession -HostName myserver -Sessions $sessions
    #>
    [CmdletBinding()]
    [OutputType([void])]
param(
        [Parameter(Mandatory = $true)]
        [string]$HostName,

        [Parameter(Mandatory = $true)]
        [array]$Sessions
    )

    if ($Sessions.Count -eq 0) {
        Write-Warning "没有可用的 tmux 会话"
        return
    }

    # 菜单分发: 统一走 GridView 主轨 (PSTui 表格)。
    # 返回对象已由 Show-TmuxSessionList 归一化, .Value 恒为纯会话名。
    # -SessionRefresher: 列表内提供"⟳ 刷新会话列表"项, 用户选中后强制重新拉取
    # (绕过 30s TTL 缓存)并重新弹出表格, 菜单打开期间不做定时轮询。
    # 刷新失败口径(2026-10-29 审计, 与 Remove/Start 侧统一): 探测命令以 `; true` 结尾,
    # 远端退出码恒为 0; 退出码非 0 必然是 SSH 连接/传输层失败 -> 抛异常, 由列表层捕获
    # -> 警告 + 保留原列表 + 允许重试; 不命中则返回会话数组(可能为空数组, 那是
    # "确实没有会话"而非失败)。
    $selected = Show-TmuxSessionList -HostName $HostName -Sessions $Sessions `
        -Title "TMUX 会话列表" -ExitLabel "返回" -ShowStateBadge `
        -SessionRefresher {
            $refreshedData = Get-TmuxSessions -HostName $HostName -Force
            if ($refreshedData.ExitCode -ne 0 -or $refreshedData.NetworkError) {
                throw "未能获取 $HostName 的 tmux 会话列表 (ssh 退出码: $($refreshedData.ExitCode))"
            }
            $refreshedData.Sessions
        }
    if ($null -eq $selected) { return }

    # 附着执行统一走 Invoke-TmuxAttach(与 Start-TmuxSession 主界面附着共用同一段语义)。
    Invoke-TmuxAttach -HostName $HostName -SessionName $selected.Value
}
