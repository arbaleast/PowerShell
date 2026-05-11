# ============================================================
# Get-TmuxSessions.ps1 — 通过 SSH 获取远程 tmux 会话列表
# ============================================================

$Global:LastSshHost = ""

function Get-TmuxSessions
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$HostName,

        [Parameter(Mandatory = $false)]
        [int]$ConnectTimeout = $global:UserScoop_CONF.SSH.ConnectTimeout
    )

    $output = ssh -o "ConnectTimeout=$ConnectTimeout" $HostName "tmux ls" 2>$null | Out-String
    $sessionList = @()

    foreach ($line in ($output -split "`n"))
    {
        if ($line -match '^[^:]+:')
        {
            $name = ($line -split ':')[0].Trim()
            $status = if ($line -match "attached")
            { "已挂载" 
            } else
            { "后台中" 
            }
            $sessionList += @{ Name = $name; Status = $status }
        }
    }

    return @{ Sessions = $sessionList; RawOutput = $output }
}

function Test-TmuxAvailable
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$HostName,

        [Parameter(Mandatory = $false)]
        [int]$ConnectTimeout = $global:UserScoop_CONF.SSH.ConnectTimeout
    )

    $result = ssh -o "ConnectTimeout=$ConnectTimeout" $HostName "command -v tmux" 2>$null
    return $null -ne $result
}
