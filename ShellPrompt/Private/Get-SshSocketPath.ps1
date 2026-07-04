# Get-SshSocketPath.ps1 - 计算 SSH ControlMaster socket 路径
# 路径约定: %TEMP%/tmux-ssh/<safeName>-<USER>@<HOST>
#   - 多用户共享同一 Windows 互不冲突
#   - 多主机各自独立 socket,避免 ControlMaster 跨主机误用
#   - %TEMP% 重启会清,避免 stale socket
# 返回 PSCustomObject { Path, Persist }; Persist 默认 600s

function Get-SshSocketPath {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SessionName,

        [Parameter()]
        [int]$Persist = 600
    )

    # socket 路径约定: %TEMP%/tmux-ssh/<SessionName>-%USERNAME%@%COMPUTERNAME%
    # 这样:
    #   1) 多用户共享同一台 Windows 时互不冲突
    #   2) 多主机各自独立 socket(避免 ControlMaster 跨主机误用)
    #   3) 重启后 %TEMP% 通常会被清理,避免 stale socket
    $user = if ($env:USERNAME) { $env:USERNAME } else { $env:USER }
    if (-not $user) { $user = 'default' }
    $hostTag = if ($env:COMPUTERNAME) { $env:COMPUTERNAME } else { [System.Net.Dns]::GetHostName() }

    # 主机名校验(同 Invoke-SshCommand 的合法字符集,防止路径注入)
    $safeName = $SessionName -replace '[^A-Za-z0-9._-]', '_'

    $socketDir = Join-Path $env:TEMP 'tmux-ssh'
    if (-not (Test-Path -LiteralPath $socketDir)) {
        try {
            $null = New-Item -ItemType Directory -Path $socketDir -Force -ErrorAction Stop
        } catch {
            # 目录创建失败时退回到系统临时目录根
            $socketDir = $env:TEMP
        }
    }

    $socketPath = Join-Path $socketDir ('{0}-{1}@{2}' -f $safeName, $user, $hostTag)

    return [PSCustomObject]@{
        Path    = $socketPath
        Persist = $Persist
    }
}
