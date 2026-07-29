function Get-SshArgs {
    <#
    .SYNOPSIS
        构建 SSH 命令行参数列表

    .DESCRIPTION
        根据提供的连接参数统一构建 ssh.exe 的参数列表，消除 Invoke-SshCommand 与
        Start-SshInteractive 中重复的参数构建代码。

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
        [switch]$CaptureOutput
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
    if ($Interactive) { [void]$sshArgs.Add('-t') }

    # 主机名作为独立参数传递（不会被 shell 解释）
    [void]$sshArgs.Add($HostName)

    # 如果提供了远程命令，则附加到参数列表
    if ($PSBoundParameters.ContainsKey('RemoteCommand')) {
        [void]$sshArgs.Add($RemoteCommand)
    }

    # 捕获输出模式强制非交互认证
    if ($CaptureOutput) {
        [void]$sshArgs.Add('-o'); [void]$sshArgs.Add('BatchMode=yes')
        [void]$sshArgs.Add('-o'); [void]$sshArgs.Add('PreferredAuthentications=publickey')
        [void]$sshArgs.Add('-o'); [void]$sshArgs.Add('NumberOfPasswordPrompts=0')
    }

    return $sshArgs
}
