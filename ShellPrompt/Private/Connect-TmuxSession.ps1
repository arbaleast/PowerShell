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
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseBOMForUnicodeEncodedFile', '')]
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
    $selected = Show-TmuxSessionList -HostName $HostName -Sessions $Sessions `
        -Title "TMUX 会话列表" -ExitLabel "返回" -ShowStateBadge `
        -SessionRefresher { (Get-TmuxSessions -HostName $HostName -Force).Sessions }
    if ($null -eq $selected) { return }

    $sessionName = $selected.Value

    $escapedName = "'$(ConvertTo-SshEscapedString -Value $sessionName)'"
    # 先 has-session 判定再决定 attach / new: 原来的 `attach ... 2>/dev/null || new-session`
    # 会把"attach 因别的原因失败"也吞成"新建一个会话", 且 stderr 被丢弃, 用户看不到原因。
    # 现在 has-session 的 stderr 照常丢弃(会话不存在是正常分支), attach 的 stderr 保留。
    $remoteCmd = "tmux has-session -t $escapedName 2>/dev/null && tmux attach -d -t $escapedName || tmux new-session -A -s $escapedName"
    $result = Invoke-SshCommand -HostName $HostName -Interactive -RemoteCommand $remoteCmd -PassThru
    if ($null -ne $result -and $result.ExitCode -ne 0) {
        Write-Warning "tmux 会话操作未成功结束 (ssh 退出码: $($result.ExitCode))，请到远端确认会话状态。"
        return
    }
    Write-Host "`n [OK] tmux 会话已分离，回到管理菜单" -ForegroundColor Cyan
}
