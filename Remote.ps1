$Global:LastSshHost = ""

# ============================================================
# Private: SSH 与 tmux 交互（纯业务逻辑，无 UI 依赖）
# ============================================================

function Get-TmuxSessions
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$HostName,

        [Parameter(Mandatory = $false)]
        [int]$ConnectTimeout = 5
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
        [int]$ConnectTimeout = 5
    )

    $result = ssh -o "ConnectTimeout=$ConnectTimeout" $HostName "command -v tmux" 2>$null
    return $null -ne $result
}

# ============================================================
# Private: 业务逻辑选择器（解耦，不涉及 UI）
# ============================================================

function Get-TmuxMenuItems
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$HostName,

        [Parameter(Mandatory = $false)]
        [int]$ConnectTimeout = 5
    )

    $defaultSession = "main"

    $menuOptions = @(
        "RESUME  — attach to '$defaultSession'",
        "ATTACH  — existing session only",
        "NEW     — create new session",
        "LIST    — view all sessions",
        "KILL    — terminate all tmux"
    )

    $mapping = @{
        "RESUME  — attach to '$defaultSession'" = @{
            Type    = "ssh"
            Command = "tmux attach -t $defaultSession || tmux new -s $defaultSession"
        }
        "ATTACH  — existing session only" = @{
            Type    = "ssh"
            Command = "tmux attach -t $defaultSession"
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
        Options = $menuOptions
        Mapping = $mapping
        DefaultSession = $defaultSession
        ConnectTimeout = $ConnectTimeout
        HostName = $HostName
    }
}

function Invoke-TmuxAction
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Action,

        [Parameter(Mandatory = $true)]
        [hashtable]$Context
    )

    $mapping = $Context.Mapping
    $hostName = $Context.HostName
    $timeout = $Context.ConnectTimeout
    $defaultSession = $Context.DefaultSession

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
                Args    = @("-o", "ConnectTimeout=$timeout", "-tt", $hostName)
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
                        Args    = @("-o", "ConnectTimeout=$timeout", "-tt", $hostName)
                    }
                }
                "list"
                {
                    $data = Get-TmuxSessions -HostName $hostName -ConnectTimeout $timeout
                    if ($data.Sessions.Count -eq 0)
                    {
                        Write-Host " [!] 无活跃会话" -ForegroundColor Yellow
                        Start-Sleep -Seconds 1
                        return $null
                    }
                    # 进入子菜单（会话选择）
                    return @{
                        Type     = "submenu"
                        Sessions = $data.Sessions
                        HostName = $hostName
                        Timeout  = $timeout
                    }
                }
            }
        }
    }

    return $null
}

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

    # 构建子菜单选项
    $subOptions = $Sessions | ForEach-Object { "$($_.Name) ($($_.Status))" }

    # 使用通用菜单组件
    $choice = Invoke-ConsoleMenu `
        -Title "TMUX MANAGER | $HostName" `
        -Options $subOptions `
        -ExitLabel "返回主菜单"

    if ($null -eq $choice)
    {
        return $null  # 返回上一级
    }

    # 找到对应的会话名
    $selectedSession = $Sessions | Where-Object { "$($_.Name) ($($_.Status))" -eq $choice } | Select-Object -First 1

    return @{
        Type    = "ssh"
        Command = "tmux attach -t '$($selectedSession.Name)'"
        Args    = @("-o", "ConnectTimeout=$ConnectTimeout", "-tt", $HostName)
    }
}

# ============================================================
# Public: 主入口
# ============================================================

function Start-TmuxSession
{
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$HostName
    )

    # 参数补全
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

    # 获取菜单数据（纯业务逻辑）
    $ctx = Get-TmuxMenuItems -HostName $HostName

    # 主循环
    while ($true)
    {
        Clear-Host
        if (Get-Command Show-UserScoopLogo -ErrorAction SilentlyContinue)
        {
            Show-UserScoopLogo
        }

        # 渲染 UI，获取用户选择
        $selection = Invoke-ConsoleMenu `
            -Title "REMOTE TMUX | $HostName" `
            -Options $ctx.Options `
            -ExitLabel "EXIT"

        if ($null -eq $selection)
        {
            return
        }

        # 执行业务逻辑
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
