# Invoke-TmuxSessionDeletion.ps1 - tmux 会话删除的**唯一屏障**(二次确认 + kill-session)
#
# 背景 (2026-10-30 TGUI 迁移):
#   旧链路里"选择会话 -> 二次确认 -> kill-session"三段逻辑全部写在
#   Remove-TmuxSession 里。TGUI 仪表盘要能直接删除**自己表格里选中的那一行**
#   (不再弹一层嵌套的 PSTui 列表), 如果照抄一份删除逻辑, 二次确认就会出现
#   两个实现 —— 迟早有人只改其中一处, 不可逆的 tmux kill-session 就可能
#   绕过唯一的防误删屏障。
#
# 因此把"会话选定之后"的删除流程抽成本文件:
#   Remove-TmuxSession(旧链路: 列表选择 -> 本函数)
#   TGUI 仪表盘(新链路: 表格选中 -> 本函数)
# 两条路径共用**同一份**二次确认与 kill-session 实现, 屏障无法被绕过。
#
# 屏障语义(与迁移前逐字一致, 不放宽):
#   - Read-SpectreConfirm 阻断式二次确认, 默认答案 'n' —— 必须显式输入 y;
#   - 确认过程抛异常(非交互终端 / Spectre 不可用) -> 按"不删除"处理,
#     绝不默认放行;
#   - ssh 启动失败(抛异常) / 退出码非 0 -> 警告 + 返回, 绝不报删除成功;
#   - 只有退出码为 0 才打印 [OK]。

function Invoke-TmuxSessionDeletion {
    <#
    .SYNOPSIS
        对**已选定**的 tmux 会话执行"二次确认 + kill-session"删除流程。

    .DESCRIPTION
        这是删除 tmux 会话的**唯一屏障实现**, 供两条调用路径共用:
          - Remove-TmuxSession: 先用 Show-TmuxSessionList 选出会话, 再调本函数;
          - TGUI 仪表盘: 直接用表格里选中的会话名调本函数。
        两条路径的确认文案、默认答案、失败口径与 [OK] 消息完全一致。

        不可逆操作保证:
          - 二次确认默认答案为 'n', 用户必须显式输入 y 才会继续;
          - 确认不可用(抛异常)时按"不删除"处理, 绝不默认放行;
          - ssh 启动失败或退出码非 0 时只警告, 绝不打印 [OK]。

    .PARAMETER HostName
        远程主机名

    .PARAMETER SessionName
        目标会话名(纯会话名, 不含任何徽章/前缀文本)

    .EXAMPLE
        Invoke-TmuxSessionDeletion -HostName myserver -SessionName 'btop'
    #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$HostName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SessionName
    )

    # 与 Remove-TmuxSession 同风格: 不可逆操作先过 ShouldProcess(-WhatIf 不落地)
    if ($PSCmdlet.ShouldProcess("tmux session '$SessionName' on $HostName", "Perform tmux kill-session")) { } else { return }

    $sessionName = $SessionName

    # 不可逆操作二次确认：默认答案为 n，用户必须显式输入 y 才会继续。
    # 提示文本交给 Spectre 渲染，[ 需转义为 [[ 才不会被当作 markup 解析。
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
