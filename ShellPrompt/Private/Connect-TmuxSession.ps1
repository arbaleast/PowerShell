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

    $sessionOptions = [System.Collections.Generic.List[PSCustomObject]]::new($Sessions.Count)
    foreach ($s in $Sessions) {
        $icon = if ($s.Status -eq "attached") { "[A]" } else { "[D]" }
        $sessionOptions.Add([PSCustomObject]@{
                Label   = "$icon $($s.Name)"
                RawName = $s.Name
                Desc    = "状态: $($s.Status)"
            })
    }

    $selected = Invoke-ConsoleMenu -Title "TMUX 会话列表 [$HostName]" -Options $sessionOptions -ExitLabel "返回"
    if ($null -eq $selected) { return }

    $sessionName = $selected.RawName
    if (-not $sessionName) {
        $sessionName = $selected.Label -replace '^\[[AD]\]\s+', ''
    }

    $escapedName = "'$(ConvertTo-SshEscapedString -Value $sessionName)'"
    Invoke-SshCommand -HostName $HostName -Interactive -RemoteCommand "tmux attach -d -t $escapedName 2>/dev/null || tmux new-session -A -s $escapedName"
    Write-Host "`n [OK] tmux 会话已分离，回到管理菜单" -ForegroundColor Cyan
}
