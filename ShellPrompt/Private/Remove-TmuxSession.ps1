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

    # 不可逆操作二次确认：默认答案为 n，用户必须显式输入 y 才会继续。
    # 提示文本交给 Spectre 渲染，[ 需转义为 [[ 才不会被当作 markup 解析。
    $sessionName = [string]$selected.Value
    $confirmMessage = ("确认删除会话 '{0}' 吗？该操作不可撤销。" -f $sessionName.Replace('[', '[['))
    $confirmed = $false
    try {
        $confirmed = Read-SpectreConfirm -Message $confirmMessage -DefaultAnswer 'n' -ConfirmFailure '已取消删除。'
    } catch {
        # Spectre 提示不可用(非交互终端等)时按"不删除"处理, 绝不默认放行
        Write-Warning "无法完成二次确认, 已放弃删除会话 '$sessionName'"
        return
    }
    if (-not $confirmed) {
        Write-Warning "已放弃删除会话 '$sessionName'"
        return
    }

    Write-Host " [..] 正在删除会话 '$sessionName' ..." -ForegroundColor DarkGray
    $escapedLabel = "'$(ConvertTo-SshEscapedString -Value $sessionName)'"
    # 必须拿到 ssh 退出码: 删除是不可逆操作, 失败时绝不能报成功。
    # ssh 启动失败(未安装 OpenSSH 客户端 / ssh.exe 不在 PATH)时 Invoke-SshCommand 会抛异常;
    # 这里降级为警告并返回, 让管理器回到主循环由用户重试, 而不是让整个 SSS 流程带异常中断。
    try {
        $result = Invoke-SshCommand -HostName $HostName -RemoteCommand "tmux kill-session -t $escapedLabel" -PassThru
    } catch {
        Write-Warning "无法执行 ssh, 删除未开始: $($_.Exception.Message)"
        return
    }
    if ($null -eq $result -or $result.ExitCode -ne 0) {
        $code = if ($null -ne $result) { $result.ExitCode } else { '未知' }
        Write-Warning "删除会话 '$sessionName' 未成功 (ssh 退出码: $code)。请在远端确认: tmux ls"
        return
    }
    Write-Host " [OK] 会话 '$sessionName' 已删除" -ForegroundColor Green
}
