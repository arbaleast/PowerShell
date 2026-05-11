# ============================================================
# Start-TmuxSession.ps1 — 远程 tmux 会话管理器（主入口）
# ============================================================

function Start-TmuxSession {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$HostName
    )

    if (-not $HostName) {
        $HostName = $Global:LastSshHost
    }
    if (-not $HostName) {
        Write-Host " [!] 缺少主机名" -ForegroundColor Red
        return
    }

    $Global:LastSshHost = $HostName
    $timeout = $global:UserScoop_CONF.SSH.ConnectTimeout
    $defaultSession = $global:UserScoop_CONF.Tmux.DefaultSessionName

    # 菜单选项与命令映射
    $menuOptions = @(
        "RESUME  — attach to '$defaultSession'",
        "ATTACH  — existing session only",
        "NEW     — create new session",
        "LIST    — view all sessions",
        "KILL    — terminate all tmux"
    )

    while ($true) {
        Clear-Host
        if (Get-Command Show-UserScoopLogo -ErrorAction SilentlyContinue) {
            Show-UserScoopLogo
        }

        $selection = Invoke-ConsoleMenu `
            -Title "REMOTE TMUX | $HostName" `
            -Options $menuOptions `
            -ExitLabel "EXIT"

        if ($null -eq $selection) {
            return
        }

        $cmd = $null

        switch ($selection) {
            "RESUME  — attach to '$defaultSession'" {
                $cmd = "tmux attach -t $defaultSession || tmux new -s $defaultSession"
            }
            "ATTACH  — existing session only" {
                $cmd = "tmux attach -t $defaultSession"
            }
            "NEW     — create new session" {
                $name = Read-Host " > 新会话名称（留空随机生成）"
                if ([string]::IsNullOrWhiteSpace($name)) {
                    $name = "G7-$(Get-Random -Min 1000 -Max 9999)"
                } elseif ($name -notmatch '^[a-zA-Z0-9_-]+$') {
                    Write-Host " [错误] 名称仅支持字母、数字和 _-" -ForegroundColor Red
                    Start-Sleep -Seconds 1
                    continue
                }
                $cmd = "tmux new -d -s '$name' && tmux attach -t '$name'"
            }
            "LIST    — view all sessions" {
                $data = Get-TmuxSessions -HostName $HostName -ConnectTimeout $timeout
                if ($data.Sessions.Count -eq 0) {
                    Write-Host " [!] 无活跃会话" -ForegroundColor Yellow
                    Start-Sleep -Seconds 1
                    continue
                }
                $subResult = Invoke-SessionSelector -Sessions $data.Sessions -HostName $HostName -ConnectTimeout $timeout
                if ($subResult -and $subResult.Type -eq "ssh") {
                    Write-Host "`n[SSH] 连接中..`n" -ForegroundColor DarkCyan
                    & ssh.exe $subResult.Args $subResult.Command
                }
                continue
            }
            "KILL    — terminate all tmux" {
                $cmd = "tmux kill-server"
            }
        }

        if ($cmd) {
            Write-Host "`n[SSH] 连接中..`n" -ForegroundColor DarkCyan
            $sshArgs = @("-o", "ConnectTimeout=$timeout", "-tt", $HostName)
            & ssh.exe $sshArgs $cmd

            Start-Sleep -Milliseconds 200
            if ($Host.UI.RawUI.KeyAvailable) {
                $Host.UI.RawUI.FlushInputBuffer()
            }
        }
    }
}
