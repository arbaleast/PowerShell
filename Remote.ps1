$Global:LastSshHost = ""

function Get-TmuxSessions
{
    param([string]$HostName)
    $output = ssh $HostName "tmux ls" 2>$null | Out-String
    $sessionList = @()
    foreach ($line in ($output -split "`n"))
    {
        if ($line -match '^[^:]+:')
        {
            $name = ($line -split ':')[0].Trim()
            $status = "后台中"
            if ($line -match "attached")
            { $status = "已挂载" 
            }
            $sessionList += @{ Name = $name; Status = $status }
        }
    }
    return @{ Sessions = $sessionList; RawOutput = $output }
}

function Test-TmuxAvailable
{
    param([string]$HostName)
    $result = ssh -o "ConnectTimeout=$($global:UserScoop_CONF.SSH.ConnectTimeout)" $HostName "command -v tmux" 2>$null
    return $null -ne $result
}

function Show-TmuxSelector
{
    param([string]$HostName, [array]$Sessions)
    $subOptions = @(@{ Name = "返回主菜单" }) + $Sessions
    $idx = 0

    while ($true)
    {
        Clear-Host
        Write-Host "$($global:UserScoop_CONF.Colors.Cyan)TMUX MANAGER | $HostName $($global:UserScoop_CONF.Colors.Rst)"

        for ($i = 0; $i -lt $subOptions.Count; $i++)
        {
            $color = "White"; $marker = "    "
            if ($i -eq $idx)
            { $color = "Cyan"; $marker = "[>] " 
            }
            $prefix = "[$i]"
            if ($i -eq 0)
            { $prefix = "[Q]" 
            }
            Write-Host "$marker $prefix $($subOptions[$i].Name) $($subOptions[$i].Status)" -ForegroundColor $color
        }

        $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        $vK = $key.VirtualKeyCode
        if ($vK -eq $global:UserScoop_CONF.Keys.Up)
        { $idx = ($idx - 1 + $subOptions.Count) % $subOptions.Count; continue 
        }
        if ($vK -eq $global:UserScoop_CONF.Keys.Down)
        { $idx = ($idx + 1) % $subOptions.Count; continue 
        }
        if ($vK -eq $global:UserScoop_CONF.Keys.Enter)
        {
            if ($idx -eq 0)
            { return "MENU_BACK" 
            }
            return "tmux attach -t '$($Sessions[$idx - 1].Name)'"
        }
        if ($key.Character -eq 'q')
        { return "MENU_BACK" 
        }
    }
}

function Invoke-TmuxAction
{
    param([string]$Key, [string]$HostName)
    $defaultSession = $global:UserScoop_CONF.Tmux.DefaultSessionName
    switch ($Key)
    {
        '1'
        { return "tmux attach -t $defaultSession || tmux new -s $defaultSession" 
        }
        '2'
        { return "tmux attach -t $defaultSession" 
        }
        '3'
        {
            $n = Read-Host " > 新会话名称(留空随机生成)"
            if ([string]::IsNullOrWhiteSpace($n))
            {
                $n = "G7-$(Get-Random -Min 1000 -Max 9999)"
            } else
            {
                if ($n -notmatch '^[a-zA-Z0-9_-]+$')
                {
                    Write-Host " [错误] 名称仅支持字母、数字和_- " -ForegroundColor Red
                    Start-Sleep -s 1
                    return $null
                }
            }
            return "tmux new -d -s '$n' && tmux attach -t '$n'"
        }
        '4'
        {
            $data = Get-TmuxSessions -HostName $HostName
            if ($data.Sessions.Count -eq 0)
            {
                Write-Host " [!] 无活跃会话" -ForegroundColor Yellow; Start-Sleep -s 1
                return "MENU_BACK"
            }
            return Show-TmuxSelector -HostName $HostName -Sessions $data.Sessions
        }
        '5'
        { return "tmux kill-server" 
        }
        'q'
        { return "INTERNAL_QUIT" 
        }
    }
    return $null
}

function Start-TmuxSession
{
    param([Parameter(Position=0)][string]$hostName)
    if (-not $hostName)
    { $hostName = $Global:LastSshHost 
    }
    if (-not $hostName)
    { Write-Host " [!] 缺少主机名" -ForegroundColor Red; return 
    }

    $Global:LastSshHost = $hostName
    $idx = 0

    $menu = @(
        @{ Name = "RESUME"; Desc = "接入 main 会话，若不存在则自动创建 (推荐)" }
        @{ Name = "ATTACH"; Desc = "仅尝试接入 main 会话 (不创建新会话)" }
        @{ Name = "NEW";    Desc = "创建新会话(输入名称，或直接回车生成随机名称)" }
        @{ Name = "LIST";   Desc = "查询该主机所有活跃会话，并打开选择面板" }
        @{ Name = "KILL";   Desc = "危险：终止该主机上运行的所有 tmux 进程" }
        @{ Name = "EXIT";   Desc = "退出当前面板，返回本地终端" }
    )

    while ($true)
    {
        Clear-Host
        if (Get-Command Show-UserScoopLogo -ErrorAction SilentlyContinue)
        { Show-UserScoopLogo 
        }
        Write-Host "$($global:UserScoop_CONF.Colors.Cyan)REMOTE TMUX | $hostName $($global:UserScoop_CONF.Colors.Rst)"
        Write-Host "$($global:UserScoop_CONF.Colors.Gray)$("-" * 50)$($global:UserScoop_CONF.Colors.Rst)"

        for ($i = 0; $i -lt $menu.Count; $i++)
        {
            $color = "White"; $marker = "    "
            if ($i -eq $idx)
            { $color = "Cyan"; $marker = "[>] " 
            }
            Write-Host "$marker[$($i+1)] $($menu[$i].Name)" -ForegroundColor $color
        }

        Write-Host ""
        Write-Host "    $($global:UserScoop_CONF.Colors.Gray)说明: $($menu[$idx].Desc)$($global:UserScoop_CONF.Colors.Rst)"
        Write-Host "$($global:UserScoop_CONF.Colors.Gray)$("-" * 50)$($global:UserScoop_CONF.Colors.Rst)"

        if ($Host.UI.RawUI.KeyAvailable)
        { $Host.UI.RawUI.FlushInputBuffer() 
        }

        $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        $vK = $key.VirtualKeyCode; $char = $key.Character.ToString().ToLower()

        if ($vK -eq $global:UserScoop_CONF.Keys.Up)
        { $idx = ($idx - 1 + $menu.Count) % $menu.Count; continue 
        }
        if ($vK -eq $global:UserScoop_CONF.Keys.Down)
        { $idx = ($idx + 1) % $menu.Count; continue 
        }

        $finalKey = $null
        if ($vK -eq $global:UserScoop_CONF.Keys.Enter)
        { $finalKey = ($idx + 1).ToString() 
        } elseif ($char -match "^[1-$($menu.Count)]$")
        { $finalKey = $char 
        } elseif ($char -eq 'q' -or $vK -eq $global:UserScoop_CONF.Keys.Esc)
        { return 
        }

        if ($finalKey -eq "$($menu.Count)")
        { return 
        }
        if ($null -ne $finalKey)
        {
            $cmd = Invoke-TmuxAction -Key $finalKey -HostName $hostName
            if ($cmd -eq "INTERNAL_QUIT")
            { return 
            }
            if ($cmd -eq "MENU_BACK" -or $null -eq $cmd)
            { continue 
            }

            Write-Host "`n[SSH] 连接中..`n" -ForegroundColor DarkCyan

            # 构建 SSH 参数
            $sshArgs = @(
                "-o", "ConnectTimeout=$($global:UserScoop_CONF.SSH.ConnectTimeout)"
            )
            if ($global:UserScoop_CONF.SSH.ForceTTy)
            {
                $sshArgs += "-tt"
            }
            $sshArgs += $hostName

            & ssh.exe $sshArgs "$cmd"

            Start-Sleep -Milliseconds 200
            if ($Host.UI.RawUI.KeyAvailable)
            { $Host.UI.RawUI.FlushInputBuffer() 
            }
        }
    }
}
