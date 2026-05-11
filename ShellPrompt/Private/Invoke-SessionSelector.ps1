# ============================================================
# Invoke-SessionSelector.ps1 — 会话选择子菜单
# ============================================================

function Invoke-SessionSelector
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [array]$Sessions,

        [Parameter(Mandatory = $true)]
        [string]$HostName,

        [Parameter(Mandatory = $false)]
        [int]$ConnectTimeout = $global:UserScoop_CONF.SSH.ConnectTimeout
    )

    $subOptions = $Sessions | ForEach-Object {
        @{ Label = $_.Name; Desc = $_.Status }
    }

    $choice = Invoke-ConsoleMenu `
        -Title "TMUX MANAGER | $HostName" `
        -Options $subOptions `
        -ExitLabel "BACK"

    if ($null -eq $choice)
    {
        return $null
    }

    return @{
        Type    = "ssh"
        Command = "tmux attach -t '$($choice.Label)'"
        Args    = @("-o", "ConnectTimeout=$ConnectTimeout", "-tt", $HostName)
    }
}
