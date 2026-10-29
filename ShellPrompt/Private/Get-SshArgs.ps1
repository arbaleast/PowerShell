function Get-SshArgs {
    <#
    .SYNOPSIS
        构建 SSH 命令行参数列表

    .DESCRIPTION
        根据提供的连接参数统一构建 ssh.exe 的参数列表，消除各 SSH 调用路径中
        重复的参数构建代码。

    .PARAMETER HostName
        远程主机名

    .PARAMETER RemoteCommand
        远程命令字符串（可选）

    .PARAMETER Interactive
        是否为交互式连接（分配 PTY）

    .PARAMETER ConnectTimeout
        SSH 连接超时（秒），默认 5

    .PARAMETER SkipHostKeyCheck
        跳过 SSH 主机密钥检查（默认关闭）

    .PARAMETER CaptureOutput
        是否为捕获输出模式（追加 BatchMode 等探测参数）

    .EXAMPLE
        $args = Get-SshArgs -HostName myserver -Interactive

    .EXAMPLE
        $args = Get-SshArgs -HostName myserver -RemoteCommand "tmux ls" -CaptureOutput
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.ArrayList])]
param(
        [Parameter(Mandatory = $true)]
        [string]$HostName,

        [Parameter(Mandatory = $false)]
        [string]$RemoteCommand,

        [Parameter(Mandatory = $false)]
        [switch]$Interactive,

        [Parameter(Mandatory = $false)]
        [int]$ConnectTimeout = 5,

        [Parameter(Mandatory = $false)]
        [switch]$SkipHostKeyCheck,

        [Parameter(Mandatory = $false)]
        [switch]$CaptureOutput,

        # 强制双 -t (ssh -tt -t): Windows OpenSSH 客户端的 PTY 模拟在单 -t 下
        # 不会回 tmux 期望的 u6/u7 终端响应, 导致 tmux "软启动后立刻 detach" (闪退)。
        # 加第二个 -t 可让 ssh 把 PTY 当作强制 tty 传给远端, 绕开 isatty 路径。
        # 探针验证 (2026-10-07): ssh -tt -t debian 'tmux attach ...' 可正常进入 tmux;
        # 单 -t 下复现 [exited]+EXIT=0 闪退。默认关闭, 只在已知路径 (New-TmuxSession) 启用。
        [Parameter(Mandatory = $false)]
        [switch]$DoubleTty
    )

    $sshArgs = New-Object System.Collections.ArrayList

    # 基础连接参数
    [void]$sshArgs.Add('-o')
    [void]$sshArgs.Add("ConnectTimeout=$ConnectTimeout")

    # 仅在显式启用时才跳过主机密钥检查（默认关闭，更安全）
    if ($SkipHostKeyCheck) {
        [void]$sshArgs.Add('-o'); [void]$sshArgs.Add('StrictHostKeyChecking=no')
        [void]$sshArgs.Add('-o'); [void]$sshArgs.Add('UserKnownHostsFile=NUL')
    }

    # 如果是交互式连接，分配 PTY（-t 标志）
    # DoubleTty 仅在 Interactive 同时启用时生效: 输出 `-tt -t`, 强制 ssh 把 PTY
    # 当作 tty 传给远端(绕过 tmux 的 isatty 检测, 修 Win OpenSSH 下的"软启动后
    # 立刻 detach"问题)
    if ($Interactive) {
        if ($DoubleTty) {
            [void]$sshArgs.Add('-tt')
        }
        [void]$sshArgs.Add('-t')
    }

    # 捕获输出模式强制非交互认证
    # (-o 选项统一放在 destination 之前: 不依赖各平台 ssh 对「destination 之后以 - 开头的
    #  参数」的解析差异, 前置写法在所有 OpenSSH 下都解析为选项)
    if ($CaptureOutput) {
        [void]$sshArgs.Add('-o'); [void]$sshArgs.Add('BatchMode=yes')
        [void]$sshArgs.Add('-o'); [void]$sshArgs.Add('PreferredAuthentications=publickey')
        [void]$sshArgs.Add('-o'); [void]$sshArgs.Add('NumberOfPasswordPrompts=0')
    }

    # 主机名作为独立参数传递（不会被 shell 解释）
    [void]$sshArgs.Add($HostName)

    # 如果提供了远程命令，则附加到参数列表
    if ($PSBoundParameters.ContainsKey('RemoteCommand')) {
        [void]$sshArgs.Add($RemoteCommand)
    }

    # 用 -NoEnumerate 写入输出流，防止单元素数组被管道逐项展开
    Write-Output -NoEnumerate $sshArgs
}
