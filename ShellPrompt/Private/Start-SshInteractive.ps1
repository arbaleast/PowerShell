# Start-SshInteractive.ps1 - 启动交互式 SSH 会话
# 性能优化: 复用 ControlMaster socket (Get-SshSocketPath) 避免重复 TCP/认证握手

. "$PSScriptRoot\Reset-TerminalMode.ps1"
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

    # 预分配 ssh 参数 List 容量,避免多次扩容
    $args = [System.Collections.Generic.List[string]]::new(8)
    [void]$args.Add('-t')
    if ($RemoteCommand) { [void]$args.Add($RemoteCommand) }
    [void]$args.Add('-o'); [void]$args.Add("ConnectTimeout=$ConnectTimeout")
    [void]$args.Add('-o'); [void]$args.Add('LogLevel=ERROR')
    if ($SkipHostKeyCheck) {
        [void]$args.Add('-o'); [void]$args.Add('StrictHostKeyChecking=no')
        [void]$args.Add('-o'); [void]$args.Add('UserKnownHostsFile=/dev/null')
    }
    if ($socket) {
        [void]$args.Add('-o'); [void]$args.Add('ControlMaster=auto')
        [void]$args.Add('-o'); [void]$args.Add("ControlPath=$($socket.Path)")
        [void]$args.Add('-o'); [void]$args.Add("ControlPersist=$($socket.Persist)")
    }
    [void]$args.Add($HostName)

    # 保存原始终端状态: Reset-TerminalMode 在 finally 块按此回滚
    $script:OriginalOutputEncoding = [Console]::OutputEncoding
    $script:OriginalInputEncoding = [Console]::InputEncoding
    $script:OriginalTerm = $env:TERM
    $env:TERM = 'xterm-256color'
    try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
    try { [Console]::InputEncoding = [System.Text.Encoding]::UTF8 } catch {}
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
