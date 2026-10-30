# Invoke-TmuxAttach.ps1 - 对单台远程主机执行 tmux 会话附着/恢复
#
# 背景 (方案 A, 2026-10-29):
#   Start-TmuxSession 改为"会话列表即主界面"后, 附着不再经由 Show-SessionManager 的
#   动作菜单触发, 而是用户在真实会话列表中直接选中会话(Enter)后立即执行。
#   为让 Connect-TmuxSession(列表选择入口) 与 Start-TmuxSession(预选会话入口)
#   共用同一段附着语义, 本文件抽出统一的执行层。
#
# 附着语义(契约, 与原 Connect-TmuxSession 保持一致):
#   先 has-session 判定, 存在则 attach(并踢掉旧附着端 -d);
#   会话已消失(显示后被其他进程删除等)时, 由 new-session -A 兜底重建并附着。
#   -d/-A 语义沿用连接-TmuxSession 的既有行为, 不因 UI 流程调整而改变。

function Invoke-TmuxAttach {
    <#
    .SYNOPSIS
        向远程主机执行 tmux 会话附着/恢复(会话名由调用方确定)。

    .DESCRIPTION
        统一附着执行层(方案 A, 2026-10-29 抽出):
          - Connect-TmuxSession: 用户在会话列表中选择会话后调用;
          - Start-TmuxSession:   会话列表作为主界面, 用户直接选中会话后调用。
        远端命令: 先 has-session 判定再决定 attach / new:
        原来的 `attach ... 2>/dev/null || new-session` 会把"attach 因别的原因失败"
        也吞成"新建一个会话", 且 stderr 被丢弃, 用户看不到原因。
        现在 has-session 的 stderr 照常丢弃(会话不存在是正常分支), attach 的 stderr 保留。
        ssh 启动失败(异常)与远端命令失败(退出码非 0)都降级为警告并返回,
        由调用方回到主循环重试, 不让异常冒泡打断整个管理器。

    .PARAMETER HostName
        远程主机名

    .PARAMETER SessionName
        目标 tmux 会话名(必须是纯会话名, 不得带 "[D]"/"● " 等徽章文本)

    .EXAMPLE
        Invoke-TmuxAttach -HostName myserver -SessionName 'btop'
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$HostName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SessionName
    )

    $escapedName = "'$(ConvertTo-SshEscapedString -Value $SessionName)'"
    $remoteCmd = "tmux has-session -t $escapedName 2>/dev/null && tmux attach -d -t $escapedName || tmux new-session -A -s $escapedName"
    # ssh 启动失败(未安装 OpenSSH 客户端 / ssh.exe 不在 PATH 等)时 Invoke-SshCommand 会抛异常。
    # 这里降级为警告并返回, 让管理器回到主循环由用户重试, 而不是让整个 SSS 流程带异常中断。
    try {
        $result = Invoke-SshCommand -HostName $HostName -Interactive -RemoteCommand $remoteCmd -PassThru
    } catch {
        Write-Warning "无法执行 ssh: $($_.Exception.Message)"
        return
    }
    if ($null -ne $result -and $result.ExitCode -ne 0) {
        Write-Warning "tmux 会话操作未成功结束 (ssh 退出码: $($result.ExitCode))，请到远端确认会话状态。"
        return
    }
    Write-Host "`n [OK] tmux 会话已分离，回到管理菜单" -ForegroundColor Cyan
}
