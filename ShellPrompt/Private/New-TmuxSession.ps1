# New-TmuxSession.ps1 - 在远程主机上创建新的 tmux 会话


function New-TmuxSession {
    <#
    .SYNOPSIS
        在远程主机上创建新的 tmux 会话

    .DESCRIPTION
        提示用户输入会话名称（或直接回车使用随机 6 位数字名称），
        然后通过 SSH 在远程主机上创建并附着到新 tmux 会话。

    .PARAMETER HostName
        远程主机名

    .EXAMPLE
        New-TmuxSession -HostName myserver
    #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    [OutputType([void])]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseBOMForUnicodeEncodedFile', '')]
param(
        [Parameter(Mandatory = $true)]
        [string]$HostName
    )
    if ($PSCmdlet.ShouldProcess("tmux session on $HostName", "Perform New-TmuxSession")) { } else { return  }

    # 菜单布局：1空行 + 3行header + N选项 + 1EXIT + 2分隔 + 1描述 + 1| + 1底边 + 2底部空行
    $optCount = 5
    $descRow = 8 + $optCount
    $inputRow = $descRow + 1

    # 颜色预解析: 统一走 Resolve-ColorTable(预热缓存 -> 配置层默认值)
    $colorTable = Resolve-ColorTable -Name 'Primary', 'Muted', 'Accent', 'Rst'
    $cp  = $colorTable.Primary
    $cm  = $colorTable.Muted
    $ca  = $colorTable.Accent
    $rst = $colorTable.Rst

    $clearEndRow = $descRow + 6
    for ($r = $descRow; $r -le $clearEndRow; $r++) {
        [Console]::Write("`e[${r};1H`e[K")
    }

    [Console]::Write("`e[$($descRow);1H  ${cp}|${rst}  ${cm}-- 输入会话名称（直接回车使用随机名称）${rst}")
    [Console]::Write("`e[$($inputRow);1H  ${cp}|${rst}  ${ca}>${rst} ")

    [Console]::CursorTop = $inputRow - 1
    [Console]::CursorLeft = 7

    try {
        $newName = [Console]::ReadLine()
    } catch {
        $newName = $null
    }

    if ([string]::IsNullOrWhiteSpace($newName)) {
        $newName = New-RandomSessionName
    }

    [Console]::Write("`e[$($inputRow + 1);1H`r`e[K")
    $escapedName = "'$(ConvertTo-SshEscapedString -Value $newName)'"
    # fix(2026-10-07): 原来 `tmux new-session -A -s $name 2>/dev/null || exec sh` 在
    # Win OpenSSH `-t` 强制 PTY 下会"软启动后立刻 detach",用户看到闪退。
    # 探针验证: 裸 `ssh -t host 'tmux new-session -s probe'` 也复现 [exited]+EXIT=0。
    # 根因: Win OpenSSH PTY 未回 tmux 期望的 u6/u7 终端响应, tmux 走 detach 路径。
    # 改法: 显式分两步, 不再吞 stderr, 也不依赖 `-A` 的隐式 attach 语义。
    #   1) has-session: 若会话已存在则 attach;  2) 否则 new-session 再 attach。
    $remoteCmd = "tmux has-session -t $escapedName 2>/dev/null && tmux attach -t $escapedName || (tmux new-session -d -s $escapedName && tmux attach -t $escapedName)"
    # DoubleTty: Win OpenSSH 下 `ssh -t` 的 PTY 不会回 tmux 期望的 u6/u7 响应,
    # tmux 走 "软启动后立刻 detach" 闪退路径。加 -tt -t 可强制 ssh 把 PTY 当作
    # tty 传给远端, 绕过 isatty 检测。raw 探针 2026-10-07 验证可修。
    $result = Invoke-SshCommand -HostName $HostName -Interactive -DoubleTty -RemoteCommand $remoteCmd -PassThru
    if ($null -ne $result -and $result.ExitCode -ne 0) {
        Write-Warning "tmux 新建/附加会话未成功结束 (ssh 退出码: $($result.ExitCode))，请到远端确认会话状态。"
        return
    }
    Write-Host "`n [OK] tmux 会话已分离，回到管理菜单" -ForegroundColor Cyan
}
