function Get-TmuxMenuItems
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$HostName,

        [Parameter(Mandatory = $false)]
        [int]$ConnectTimeout = $global:UserScoop_CONF.SSH.ConnectTimeout,

        [Parameter(Mandatory = $false)]
        [string]$DefaultSessionName = $global:UserScoop_CONF.Tmux.DefaultSessionName
    )

    $menuOptions = @(
        "RESUME  — attach to '$DefaultSessionName'",
        "ATTACH  — existing session only",
        "NEW     — create new session",
        "LIST    — view all sessions",
        "KILL    — terminate all tmux"
    )

    $mapping = @{
        "RESUME  — attach to '$DefaultSessionName'" = @{
            Type    = "ssh"
            Command = "tmux attach -t $DefaultSessionName || tmux new -s $DefaultSessionName"
        }
        "ATTACH  — existing session only" = @{
            Type    = "ssh"
            Command = "tmux attach -t $DefaultSessionName"
        }
        "NEW     — create new session" = @{
            Type    = "interactive"
            Command = "new"
        }
        "LIST    — view all sessions" = @{
            Type    = "interactive"
            Command = "list"
        }
        "KILL    — terminate all tmux" = @{
            Type    = "ssh"
            Command = "tmux kill-server"
        }
    }

    return @{
        Options        = $menuOptions
        Mapping        = $mapping
        DefaultSession = $DefaultSessionName
        ConnectTimeout = $ConnectTimeout
        HostName       = $HostName
    }
}

function Invoke-TmuxAction
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Action,

        [Parameter(Mandatory = $true)]
        [hashtable]$Context,

        [Parameter(Mandatory = $false)]
        [int]$ConnectTimeout = $global:UserScoop_CONF.SSH.ConnectTimeout
    )

    $mapping = $Context.Mapping
    $hostName = $Context.HostName

    if (-not $mapping.ContainsKey($Action))
    {
        return $null
    }

    $entry = $mapping[$Action]

    switch ($entry.Type)
    {
        "ssh"
        {
            return @{
                Type    = "ssh"
                Command = $entry.Command
                Args    = @("-o", "ConnectTimeout=$ConnectTimeout", "-tt", $hostName)
            }
        }
        "interactive"
        {
            switch ($entry.Command)
            {
                "new"
                {
                    $name = Read-Host " > 新会话名称（留空随机生成）"
                    if ([string]::IsNullOrWhiteSpace($name))
                    {
                        $name = "G7-$(Get-Random -Min 1000 -Max 9999)"
                    } elseif ($name -notmatch '^[a-zA-Z0-9_-]+$')
                    {
                        Write-Host " [错误] 名称仅支持字母、数字和 _-" -ForegroundColor Red
                        Start-Sleep -Seconds 1
                        return $null
                    }
                    return @{
                        Type    = "ssh"
                        Command = "tmux new -d -s '$name' && tmux attach -t '$name'"
                        Args    = @("-o", "ConnectTimeout=$ConnectTimeout", "-tt", $hostName)
                    }
                }
                "list"
                {
                    $data = Get-TmuxSessions -HostName $hostName -ConnectTimeout $ConnectTimeout
                    if ($data.Sessions.Count -eq 0)
                    {
                        Write-Host " [!] 无活跃会话" -ForegroundColor Yellow
                        Start-Sleep -Seconds 1
                        return $null
                    }
                    return @{
                        Type     = "submenu"
                        Sessions = $data.Sessions
                        HostName = $hostName
                        Timeout  = $ConnectTimeout
                    }
                }
            }
        }
    }

    return $null
}
