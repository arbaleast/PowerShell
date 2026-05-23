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

    if (-not (Get-Command ssh.exe -ErrorAction SilentlyContinue)) {
        Write-Host " [!] ssh.exe 未找到，请确保 OpenSSH 已安装并在 PATH 中" -ForegroundColor Red
        return
    }

    # 精简选项，每项带描述
    $menuOptions = @(
        @{ Label = "RESUME"; Desc = "attach to '$defaultSession', create if missing" }
        @{ Label = "ATTACH"; Desc = "attach only, never create" }
        @{ Label = "NEW"; Desc = "create a new named session" }
        @{ Label = "LIST"; Desc = "pick from active sessions on host" }
        @{ Label = "KILL"; Desc = "terminate ALL tmux sessions on host" }
    )

    while ($true) {
        # 每次循环开始时重置终端状态，防止远程断开后的残留问题
        Clear-Host
        if (Get-Command Show-UserScoopLogo -ErrorAction SilentlyContinue) {
            Show-UserScoopLogo
        }

        $selection = Invoke-ConsoleMenu `
            -Title "REMOTE TMUX | $HostName" `
            -Options $menuOptions `
            -ExitLabel "EXIT"

        if ($null -eq $selection) {
            # 退出时清除菜单残留内容，确保终端回到干净状态
            Clear-Host
            return
        }

        $label = $selection.Label
        $cmd = $null
        $fallbackSsh = $false

        switch ($label) {
            "RESUME" {
                # 检查远程是否有 tmux
                if (Test-TmuxAvailable -HostName $HostName -ConnectTimeout $timeout) {
                    $cmd = "tmux attach -t $defaultSession 2>/dev/null || tmux new -s $defaultSession"
                } else {
                    # 无 tmux fallback：直接 SSH 登录
                    $cmd = $null
                    $fallbackSsh = $true
                }
            }
            "ATTACH" {
                if (Test-TmuxAvailable -HostName $HostName -ConnectTimeout $timeout) {
                    $cmd = 'if tmux has-session -t ' + $defaultSession + ' >/dev/null 2>&1; then tmux attach -t ' + $defaultSession + '; else echo ''tmux session "' + $defaultSession + '" not found'' >&2; exit 1; fi'
                } else {
                    $cmd = $null
                    $fallbackSsh = $true
                }
            }
            "NEW" {
                # 清除菜单，清空描述区域准备输入
                [Console]::Write("`e[2J`e[H`e[0m")
                Write-Host "" 
                $name = Read-Host "session name (Enter = random)"
                if ([string]::IsNullOrWhiteSpace($name)) {
                    $name = "G7-$(Get-Random -Min 1000 -Max 9999)"
                } elseif ($name -match '[\s''"\\`]') {
                    Write-Host " [错误] 会话名不能包含空格、引号、反引号或反斜杠" -ForegroundColor Red
                    Start-Sleep -Seconds 1
                    continue
                }
                $cmd = "tmux new -d -s '$name' && tmux attach -t '$name'"
            }
            "LIST" {
                $data = Get-TmuxSessions -HostName $HostName -ConnectTimeout $timeout
                if ($data.Sessions.Count -eq 0) {
                    Write-Host "`n [!] 无活跃会话" -ForegroundColor Yellow
                    Start-Sleep -Seconds 1
                    continue
                }
                $subResult = Invoke-SessionSelector -Sessions $data.Sessions -HostName $HostName -ConnectTimeout $timeout
                if ($subResult -and $subResult.Type -eq "ssh") {
                    # 清空菜单，在底部显示连接提示
                    Clear-Host
                    Write-Host "`n`n`n[SSH] 连接中..`n" -ForegroundColor DarkCyan
                    & ssh.exe $subResult.Args $subResult.Command

                    # SSH 连接结束后，完整重置终端状态（解决光标错位、清屏失效等问题）
                    [Console]::Write("`e[2J`e[H`e[0m`e[?25h`e[?3l`e[!p")
                }
                continue
            }
            "KILL" {
                $cmd = "tmux kill-server"
            }
        }

        if ($cmd) {
            # 清空菜单，在底部显示连接提示
            Clear-Host
            Write-Host "`n`n`n[SSH] 连接中..`n" -ForegroundColor DarkCyan
            $sshArgs = @("-o", "ConnectTimeout=$timeout", "-tt", $HostName, $cmd)
            & ssh.exe @sshArgs
            $sshExitCode = $LASTEXITCODE

            # SSH 连接结束（包括远程断开）后，完整重置终端状态
            # 解决：卡死、光标错位、清屏失效等远程断开后的遗留问题
            [Console]::Write("`e[2J`e[H`e[0m`e[?25h`e[?3l`e[!p")

            if ($sshExitCode -ne 0) {
                if ($sshExitCode -eq 255) {
                    Write-Host " [!] SSH 连接失败，请检查主机名、网络和 OpenSSH 配置" -ForegroundColor Yellow
                } else {
                    Write-Host " [!] SSH / tmux 命令执行失败，退出码: $sshExitCode" -ForegroundColor Yellow
                }
                Start-Sleep -Seconds 1
            }

            # 短暂延迟后清空输入缓冲区，确保远程断开时的残留按键不会影响下次菜单
            Start-Sleep -Milliseconds 200
            if ($Host.UI.RawUI.KeyAvailable) {
                $Host.UI.RawUI.FlushInputBuffer()
            }
        } elseif ($fallbackSsh) {
            # 远程无 tmux，直接 SSH 登录
            # 清空菜单，在底部显示连接提示
            Clear-Host
            Write-Host "`n`n`n[SSH] 远程无 tmux，直接连接中..`n" -ForegroundColor DarkCyan
            $sshArgs = @("-o", "ConnectTimeout=$timeout", "-tt", $HostName)
            & ssh.exe @sshArgs
            $sshExitCode = $LASTEXITCODE

            [Console]::Write("`e[2J`e[H`e[0m`e[?25h`e[?3l`e[!p")

            if ($sshExitCode -ne 0) {
                if ($sshExitCode -eq 255) {
                    Write-Host " [!] SSH 连接失败，请检查主机名、网络和 OpenSSH 配置" -ForegroundColor Yellow
                } else {
                    Write-Host " [!] SSH 连接失败，退出码: $sshExitCode" -ForegroundColor Yellow
                }
                Start-Sleep -Seconds 1
            }

            Start-Sleep -Milliseconds 200
            if ($Host.UI.RawUI.KeyAvailable) {
                $Host.UI.RawUI.FlushInputBuffer()
            }
        }
    }
}
