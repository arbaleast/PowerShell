function Start-TmuxSession
{
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$HostName
    )

    if (-not $HostName)
    {
        $HostName = $Global:LastSshHost
    }
    if (-not $HostName)
    {
        Write-Host " [!] 缺少主机名" -ForegroundColor Red
        return
    }

    $Global:LastSshHost = $HostName
    $ctx = Get-TmuxMenuItems -HostName $HostName

    while ($true)
    {
        Clear-Host
        if (Get-Command Show-UserScoopLogo -ErrorAction SilentlyContinue)
        {
            Show-UserScoopLogo
        }

        $selection = Invoke-ConsoleMenu `
            -Title "REMOTE TMUX | $HostName" `
            -Options $ctx.Options `
            -ColorCyan $global:UserScoop_CONF.Colors.Cyan `
            -ColorGray $global:UserScoop_CONF.Colors.Gray `
            -Keys $global:UserScoop_CONF.Keys `
            -ExitLabel "EXIT"

        if ($selection -eq "MENU_BACK")
        {
            return
        }

        $result = Invoke-TmuxAction -Action $selection -Context $ctx

        if ($null -eq $result)
        {
            continue
        }

        switch ($result.Type)
        {
            "ssh"
            {
                Write-Host "`n[SSH] 连接中..`n" -ForegroundColor DarkCyan
                & ssh.exe $result.Args $result.Command

                Start-Sleep -Milliseconds 200
                if ($Host.UI.RawUI.KeyAvailable)
                {
                    $Host.UI.RawUI.FlushInputBuffer()
                }
            }
            "submenu"
            {
                $subResult = Invoke-SessionSelector `
                    -Sessions $result.Sessions `
                    -HostName $result.HostName `
                    -ConnectTimeout $result.Timeout

                if ($null -ne $subResult -and $subResult.Type -eq "ssh")
                {
                    Write-Host "`n[SSH] 连接中..`n" -ForegroundColor DarkCyan
                    & ssh.exe $subResult.Args $subResult.Command

                    Start-Sleep -Milliseconds 200
                    if ($Host.UI.RawUI.KeyAvailable)
                    {
                        $Host.UI.RawUI.FlushInputBuffer()
                    }
                }
            }
        }
    }
}
