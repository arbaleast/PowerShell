# ============================================================
# Get-TmuxSessions.ps1 - 通过 SSH 获取远程 tmux 会话列表
# 变更记录:
#   - 移除 $Global:LastSshHost 全局变量声明（移至 psm1 统一管理）
#   - 改用 Invoke-SshCommand 统一执行 SSH 调用（防止命令注入）
#   - [2026-05-23] 修复: 严格检查 tmux 输出格式，防止误解析非会话行（如 SSH banner/MOTD）
#   - [2026-05-23] 修复: 验证 SSH 命令执行成功后再解析输出（检查退出码）
# ============================================================

function Get-TmuxSessions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$HostName,

        [Parameter(Mandatory = $false)]
        [int]$ConnectTimeout = $global:UserScoop_CONF.SSH.ConnectTimeout
    )

    try {
        # 使用 Invoke-SshCommand 统一执行 SSH 调用（防止命令注入）
        # 使用 -PassThru 参数获取 SSH 进程的退出码，确保命令执行成功
        $result = Invoke-SshCommand -HostName $HostName -RemoteCommand "tmux ls 2>/dev/null" -CaptureOutput -ConnectTimeout $ConnectTimeout -PassThru
    } catch {
        if ($Global:TUI_Logger) {
            $Global:TUI_Logger.Warning("SSH 获取 tmux 会话失败: $($_.Exception.Message)", @{ Host = $HostName })
        }
        return @{ Sessions = New-Object System.Collections.ArrayList; RawOutput = "" }
    }
    
    # 检查 SSH 命令是否成功执行（退出码为 0）
    # Invoke-SshCommand -PassThru 返回包含 Output 和 ExitCode 的对象
    if ($null -eq $result.ExitCode -or $result.ExitCode -ne 0) {
        # SSH 连接失败或不稳定，输出不可信，返回空列表
        if ($Global:TUI_Logger) {
            $Global:TUI_Logger.Warning("SSH 执行 tmux ls 失败（退出码: $($result.ExitCode)）", @{ Host = $HostName })
        }
        return @{ Sessions = New-Object System.Collections.ArrayList; RawOutput = $result.Output }
    }
    
    $output = $result.Output
    
    # 安全检查：空输出或仅含空白字符 => 远程 tmux 无会话
    if ([string]::IsNullOrWhiteSpace($output)) {
        return @{ Sessions = New-Object System.Collections.ArrayList; RawOutput = $output }
    }

    $sessionList = New-Object System.Collections.ArrayList

    # 严格模式的 tmux 输出解析格式
    # tmux ls 标准输出格式:
    #   main: 1 windows (created Mon May 23 12:00:00 2026) (attached)
    #   tmux-123456: 1 windows (created ...) (detached)
    # 关键特征: 会话名后跟冒号 + 空格 + 数字 + windows + (created
    # 只匹配标准 tmux ls 格式行，避免误解析 SSH banner/warning/MOTD 等
    $tmuxLineRegex = '^([^:]+):\s+\d+\s+windows?\s+\(created'

    foreach ($line in ($output -split "`n")) {
        $line = $line.Trim()
        if ($line -match $tmuxLineRegex) {
            $name = $matches[1].Trim()
            $status = if ($line -match "attached") { "attached" } else { "detached" }
            $sessionList.Add([PSCustomObject]@{ Name = $name; Status = $status }) | Out-Null
        }
    }

    return @{ Sessions = $sessionList; RawOutput = $output }
}

function Test-TmuxAvailable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$HostName,

        [Parameter(Mandatory = $false)]
        [int]$ConnectTimeout = $global:UserScoop_CONF.SSH.ConnectTimeout
    )

    try {
        # 使用 Invoke-SshCommand 统一执行 SSH 调用
        $result = Invoke-SshCommand -HostName $HostName -RemoteCommand "command -v tmux" -CaptureOutput -ConnectTimeout $ConnectTimeout -PassThru
        # 检查退出码：0 表示 tmux 可用，非 0 表示不可用
        return ($null -ne $result.ExitCode -and $result.ExitCode -eq 0)
    } catch {
        return $false
    }
}

# ============================================================
# 本地多终端复用器检测
# 支持 tmux、screen、byobu（仅在本地使用，不涉及 SSH）
# ============================================================
function Get-MultiplexerSessions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$HostName = "localhost"
    )
    
    $result = @{
        Detected  = $null
        Available = $false
        Sessions  = @()
        RawOutput = ""
    }
    
    $multiplexers = @('tmux', 'byobu', 'screen')
    
    foreach ($mux in $multiplexers) {
        $cmd = Get-Command $mux -ErrorAction SilentlyContinue
        if ($cmd) {
            $result.Detected = $mux
            $result.Available = $true
             
            $sessions = switch ($mux) {
                'tmux' {
                    & tmux list-sessions 2>$null | ForEach-Object {
                        if ($_ -match '^([^:]+)') {
                            [PSCustomObject]@{
                                Name   = $matches[1]
                                Status = if ($_ -match "attached") { "attached" } else { "detached" }
                            }
                        }
                    }
                }
                'screen' {
                    & screen -ls 2>$null | ForEach-Object {
                        if ($_ -match '^\s*(\d+)\s*\(([^)]+)\)') {
                            [PSCustomObject]@{
                                Name   = $matches[1]
                                Status = if ($matches[2] -match "Attached") { "attached" } else { "detached" }
                            }
                        }
                    }
                }
                'byobu' {
                    $backend = & byobu-launcher-import tmux 2>$null
                    if ($backend -eq "tmux") {
                        & tmux list-sessions 2>$null | ForEach-Object {
                            if ($_ -match '^([^:]+)') {
                                [PSCustomObject]@{
                                    Name   = $matches[1]
                                    Status = if ($_ -match "attached") { "attached" } else { "detached" }
                                }
                            }
                        }
                    }
                }
            }
             
            if ($sessions) {
                $result.Sessions = @($sessions)
            }
            break
        }
    }
     
    return $result
}

function Test-MultiplexerAvailable {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Type = $null
    )
     
    if ($Type) {
        return $null -ne (Get-Command $Type -ErrorAction SilentlyContinue)
    }
     
    return (Test-Path (Get-Command tmux -ErrorAction SilentlyContinue).Source) -or
    (Test-Path (Get-Command screen -ErrorAction SilentlyContinue).Source) -or
    (Test-Path (Get-Command byobu -ErrorAction SilentlyContinue).Source)
}
