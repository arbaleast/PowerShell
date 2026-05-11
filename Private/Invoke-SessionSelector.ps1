function Invoke-SessionSelector
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [array]$Sessions,

        [Parameter(Mandatory = $true)]
        [string]$HostName,

        [Parameter(Mandatory = $false)]
        [int]$ConnectTimeout = 5
    )

    $subOptions = $Sessions | ForEach-Object { "$($_.Name) ($($_.Status))" }

    $choice = Invoke-ConsoleMenu `
        -Title "TMUX MANAGER | $HostName" `
        -Options $subOptions `
        -ExitLabel "返回主菜单"

    if ($null -eq $choice)
    {
        return $null
    }

    $selectedSession = $Sessions | Where-Object {
        "$($_.Name) ($($_.Status))" -eq $choice
    } | Select-Object -First 1

    return @{
        Type    = "ssh"
        Command = "tmux attach -t '$($selectedSession.Name)'"
        Args    = @("-o", "ConnectTimeout=$ConnectTimeout", "-tt", $HostName)
    }
}
