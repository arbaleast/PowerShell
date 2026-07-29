# Start-SshInteractive.ps1 - 启动交互式 SSH 会话
# 性能优化: 复用 ControlMaster socket (Get-SshSocketPath) 避免重复 TCP/认证握手

. "$PSScriptRoot\Get-SshSocketPath.ps1"

function Start-SshInteractive {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$HostName,
        [Parameter()]
        [string]$RemoteCommand,
        [Parameter()]
        [ValidateRange(1, 300)]
        [int]$ConnectTimeout = 5,
        [Parameter()]
        [switch]$SkipHostKeyCheck,
        [Parameter()]
        [switch]$PassThru
    )

    # ControlMaster socket 缓存: 按主机名复用已建立的 master 连接
    $socket = $null
    if ($script:SshSocketCache -and $script:SshSocketCache.ContainsKey($HostName)) {
        $socket = $script:SshSocketCache[$HostName]
    } else {
        try {
            $socket = Get-SshSocketPath -SessionName $HostName
        } catch {
            $socket = $null
        }
        if (-not $script:SshSocketCache) { $script:SshSocketCache = @{} }
        $script:SshSocketCache[$HostName] = $socket
    }

    # 委托 Get-SshArgs 构建基础 SSH 参数（始终以交互模式运行）
    $args = Get-SshArgs -HostName $HostName -RemoteCommand $RemoteCommand `
        -Interactive -ConnectTimeout $ConnectTimeout -SkipHostKeyCheck:$SkipHostKeyCheck

    # ControlMaster 专属参数（Get-SshArgs 不处理此部分）
    if ($socket) {
        [void]$args.Add('-o'); [void]$args.Add('LogLevel=ERROR')
        [void]$args.Add('-o'); [void]$args.Add('ControlMaster=auto')
        [void]$args.Add('-o'); [void]$args.Add("ControlPath=$($socket.Path)")
        [void]$args.Add('-o'); [void]$args.Add("ControlPersist=$($socket.Persist)")
    }

    # 保存原始终端状态: Reset-TerminalMode 在 finally 块按此回滚
    Save-OriginalTerminalState
    try {
        $proc = Start-Process -FilePath 'ssh' -ArgumentList $args -NoNewWindow -Wait -PassThru
        $exitCode = if ($proc.ExitCode -ne $null) { [int]$proc.ExitCode } else { 0 }
    } finally {
        Reset-TerminalMode
    }
    if ($PassThru) {
        [pscustomobject]@{
            Output   = ''
            Error    = ''
            ExitCode = $exitCode
        }
    }
}

# 此函数为 Private 辅助:ShellPrompt.psm1 Export-ModuleMember 白名单控制导出,
# 本文件无需再声明 Export-ModuleMember。
