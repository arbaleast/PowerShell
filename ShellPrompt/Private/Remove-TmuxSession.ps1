# Remove-TmuxSession.ps1 - 删除远程 tmux 会话


function Remove-TmuxSession {
    <#
    .SYNOPSIS
        通过交互式菜单选择并删除远程 tmux 会话

    .DESCRIPTION
        展示远程主机上的 tmux 会话列表，用户选择后通过 SSH kill-session 删除目标会话。

    .PARAMETER HostName
        远程主机名

    .PARAMETER Sessions
        会话列表（由 Get-TmuxSessions 返回的 PSCustomObject 数组）

    .EXAMPLE
        Remove-TmuxSession -HostName myserver -Sessions $sessions
    #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    [OutputType([void])]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseBOMForUnicodeEncodedFile', '')]
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

    $killOptions = [System.Collections.Generic.List[PSCustomObject]]::new($Sessions.Count)
    foreach ($s in $Sessions) {
        $killOptions.Add([PSCustomObject]@{ Label = $s.Name; Desc = "状态: $($s.Status)" })
    }

    $selected = Invoke-ConsoleMenu -Title "删除 TMUX 会话 [$HostName]" -Options $killOptions -ExitLabel "取消"
    if ($null -eq $selected) { return }

    Write-Host " [..] 正在删除会话 '$($selected.Label)' ..." -ForegroundColor DarkGray
    $escapedLabel = "'$(ConvertTo-SshEscapedString -Value $selected.Label)'"
    Invoke-SshCommand -HostName $HostName -RemoteCommand "tmux kill-session -t $escapedLabel"
    Write-Host " [OK] 会话 '$($selected.Label)' 已删除" -ForegroundColor Green
}
