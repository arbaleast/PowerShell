# ============================================================
# Start-TmuxSession.ps1 — 远程 tmux 会话管理器（主入口）
# ============================================================

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
    $timeout = $global:UserScoop_CONF.SSH.ConnectTimeout
    $defaultSession = $global:UserScoop_CONF.Tmux.DefaultSessionName

    # 精简选项，每项带描述
    $menuOptions = @(
        @{ Label = "RESUME";   Desc = "attach to '$defaultSession', create if missing" }
        @{ Label = "ATTACH";   Desc = "attach only, never create" }
        @{ Label = "NEW";      Desc = "create a new named session" }
        @{ Label = "LIST";     Desc = "pick from active sessions on host" }
        @{ Label = "KILL";     Desc = "terminate ALL tmux sessions on host" }
    )

    while ($true)
    {
        Clear-Host
        if (Get-Command Show-UserScoopLogo -ErrorAction SilentlyContinue)
        {
            Show-UserScoopLogo
        }

        $selection = Invoke-ConsoleMenu `
            -Title "REMOTE TMUX | $HostName" `
            -Options $menuOptions `
            -ExitLabel "EXIT"

        if ($null -eq $selection)
        {
            return
        }

        $label = $selection.Label
        $cmd = $null

        switch ($label)
        {
            "RESUME"
            {
                $cmd = "tmux attach -t $defaultSession || tmux new -s $defaultSession"
            }
            "ATTACH"
            {
                $cmd = "tmux attach -t $defaultSession"
            }
            "NEW"
            {
                $name = Read-Host "`n > session name (Enter = random)"
                if ([string]::IsNullOrWhiteSpace($name))
                {
                    $name = "G7-$(Get-Random -Min 1000 -Max 9999)"
                } elseif ($name -notmatch '^[a-zA-Z0-9_-]+$')
                {
                    Write-Host " [错误] 仅支持字母、数字、_、-" -ForegroundColor Red
                    Start-Sleep -Seconds 1
                    continue
                }
                $cmd = "tmux new -d -s '$name' && tmux attach -t '$name'"
            }
            "LIST"
            {
                $data = Get-TmuxSessions -HostName $HostName -ConnectTimeout $timeout
                if ($data.Sessions.Count -eq 0)
                {
                    Write-Host "`n [!] 无活跃会话" -ForegroundColor Yellow
                    Start-Sleep -Seconds 1
                    continue
                }
                $subResult = Invoke-SessionSelector -Sessions $data.Sessions -HostName $HostName -ConnectTimeout $timeout
                if ($subResult -and $subResult.Type -eq "ssh")
                {
                    Write-Host "`n[SSH] 连接中..`n" -ForegroundColor DarkCyan
                    & ssh.exe $subResult.Args $subResult.Command
                }
                continue
            }
            "KILL"
            {
                $cmd = "tmux kill-server"
            }
        }

        if ($cmd)
        {
            Write-Host "`n[SSH] 连接中..`n" -ForegroundColor DarkCyan
            $sshArgs = @("-o", "ConnectTimeout=$timeout", "-tt", $HostName)
            & ssh.exe $sshArgs $cmd

            Start-Sleep -Milliseconds 200
            if ($Host.UI.RawUI.KeyAvailable)
            {
                $Host.UI.RawUI.FlushInputBuffer()
            }
        }
    }
}
